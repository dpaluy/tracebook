# frozen_string_literal: true

require "test_helper"
require "socket"

module Tracebook
  module Redaction
    class OpenAiPrivacyFilterTest < ActiveSupport::TestCase
      FakeClient = Data.define(:response) do
        def detect(_text)
          response
        end
      end

      class RecordingClient
        attr_reader :texts

        def initialize(*responses)
          @responses = responses
          @texts = []
        end

        def detect(text)
          texts << text
          response = @responses.shift || {}
          raise response if response.is_a?(Exception)

          response
        end
      end

      class RaisingClient
        def detect(_text)
          raise OpenAiPrivacyFilter::ClientError, "unavailable"
        end
      end

      class TimeoutClient
        def detect(_text)
          raise Net::ReadTimeout, "execution expired"
        end
      end

      test "applies detected spans with stable placeholders" do
        redactor = OpenAiPrivacyFilter.new(
          client: FakeClient.new({
            "detected_spans" => [
              { "start" => 0, "end" => 5, "label" => "private_person" },
              { "start" => 15, "end" => 25, "label" => "private_date" }
            ]
          })
        )

        assert_equal "[PERSON] was born [DATE].",
          redactor.call("Alice was born 1990-01-02.")
      end

      test "accepts spans alias and custom label map" do
        redactor = OpenAiPrivacyFilter.new(
          label_map: { private_person: "[NAME]" },
          client: FakeClient.new({
            "spans" => [
              { "start" => 0, "end" => 5, "label" => "private_person" }
            ]
          })
        )

        assert_equal "[NAME] emailed support", redactor.call("Alice emailed support")
      end

      test "ignores unknown and invalid spans" do
        redactor = OpenAiPrivacyFilter.new(
          client: FakeClient.new({
            "detected_spans" => [
              { "start" => 0, "end" => 5, "label" => "unknown" },
              { "start" => 10, "end" => 50, "label" => "private_person" },
              { "start" => 6, "end" => 9, "label" => "private_date" }
            ]
          })
        )

        assert_equal "Alice [DATE]", redactor.call("Alice Jan")
      end

      test "keeps the longest span when spans overlap at the same start" do
        redactor = OpenAiPrivacyFilter.new(
          client: FakeClient.new({
            "detected_spans" => [
              { "start" => 0, "end" => 5, "label" => "private_person" },
              { "start" => 0, "end" => 11, "label" => "private_person" }
            ]
          })
        )

        assert_equal "[PERSON]", redactor.call("Alice Smith")
      end

      test "merges adjacent spans with the same label into one placeholder" do
        redactor = OpenAiPrivacyFilter.new(
          client: FakeClient.new({
            "detected_spans" => [
              { "start" => 0, "end" => 5, "label" => "private_person" },
              { "start" => 5, "end" => 10, "label" => "private_person" }
            ]
          })
        )

        assert_equal "[PERSON]", redactor.call("AliceSmith")
      end

      test "propagates detected scoped substrings to later messages" do
        address = "12822 Majestic Oaks Dr"
        first_message = "I live at #{address}"
        first_start = first_message.index(address)
        client = RecordingClient.new(
          {
            "detected_spans" => [
              { "start" => first_start, "end" => first_start + address.length, "label" => "private_address" }
            ]
          },
          { "detected_spans" => [] }
        )
        redactor = OpenAiPrivacyFilter.new(client: client)

        assert_equal "I live at [ADDRESS]", redactor.call(first_message, scope: "chat-1")
        assert_equal "Nearest hospital to [ADDRESS]",
          redactor.call("Nearest hospital to #{address}", scope: "chat-1")
        assert_equal [
          first_message,
          "Nearest hospital to [ADDRESS]"
        ], client.texts
      end

      test "does not propagate scoped substrings across scopes" do
        client = RecordingClient.new(
          {
            "detected_spans" => [
              { "start" => 0, "end" => 5, "label" => "private_person" }
            ]
          },
          { "detected_spans" => [] }
        )
        redactor = OpenAiPrivacyFilter.new(client: client)

        assert_equal "[PERSON]", redactor.call("Alice", scope: "chat-1")
        assert_equal "Alice", redactor.call("Alice", scope: "chat-2")
      end

      test "caches scoped redaction results by scope and original text" do
        client = RecordingClient.new(
          {
            "detected_spans" => [
              { "start" => 0, "end" => 5, "label" => "private_person" }
            ]
          }
        )
        redactor = OpenAiPrivacyFilter.new(client: client)

        assert_equal "[PERSON]", redactor.call("Alice", scope: "chat-1")
        assert_equal "[PERSON]", redactor.call("Alice", scope: "chat-1")
        assert_equal [ "Alice" ], client.texts
      end

      test "invalidates cached scoped results when new private substrings are recorded" do
        address = "12822 Majestic Oaks Dr"
        assistant_message = "Nearest hospital to #{address}"
        user_message = "I live at #{address}"
        user_start = user_message.index(address)
        client = RecordingClient.new(
          { "detected_spans" => [] },
          {
            "detected_spans" => [
              { "start" => user_start, "end" => user_start + address.length, "label" => "private_address" }
            ]
          },
          { "detected_spans" => [] }
        )
        redactor = OpenAiPrivacyFilter.new(client: client)

        assert_equal assistant_message, redactor.call(assistant_message, scope: "chat-1")
        assert_equal "I live at [ADDRESS]", redactor.call(user_message, scope: "chat-1")
        assert_equal "Nearest hospital to [ADDRESS]", redactor.call(assistant_message, scope: "chat-1")
        assert_equal [
          assistant_message,
          user_message,
          "Nearest hospital to [ADDRESS]"
        ], client.texts
      end

      test "applies the longest remembered scoped substring first" do
        full_address = "12822 Majestic Oaks Dr, Austin, TX 78732"
        redactor = OpenAiPrivacyFilter.new(client: FakeClient.new({ "detected_spans" => [] }))
        scoped_memory = redactor.send(:scoped_memory)
        scoped_memory.record("chat-1", "12822 Majestic Oaks Dr", "private_address")
        scoped_memory.record("chat-1", full_address, "private_address")

        assert_equal "Nearest hospital to [ADDRESS]",
          redactor.call("Nearest hospital to #{full_address}", scope: "chat-1")
      end

      test "scoped sidecar failures keep memory redactions but are not cached" do
        address = "12822 Majestic Oaks Dr"
        client = RecordingClient.new(
          OpenAiPrivacyFilter::ClientError.new("unavailable"),
          { "detected_spans" => [] }
        )
        redactor = OpenAiPrivacyFilter.new(client: client)
        redactor.send(:scoped_memory).record("chat-1", address, "private_address")

        assert_equal "Nearest hospital to [ADDRESS]",
          redactor.call("Nearest hospital to #{address}", scope: "chat-1")
        assert_equal "Nearest hospital to [ADDRESS]",
          redactor.call("Nearest hospital to #{address}", scope: "chat-1")
        assert_equal [
          "Nearest hospital to [ADDRESS]",
          "Nearest hospital to [ADDRESS]"
        ], client.texts
      end

      test "returns input text when sidecar is unavailable" do
        redactor = OpenAiPrivacyFilter.new(client: RaisingClient.new)

        assert_equal "Email [EMAIL]", redactor.call("Email [EMAIL]")
      end

      test "returns input text when sidecar times out" do
        redactor = OpenAiPrivacyFilter.new(client: TimeoutClient.new)

        assert_equal "Email [EMAIL]", redactor.call("Email [EMAIL]")
      end

      test "can raise on sidecar failures when configured" do
        redactor = OpenAiPrivacyFilter.new(client: RaisingClient.new, failure_mode: :raise)

        assert_raises OpenAiPrivacyFilter::ClientError do
          redactor.call("Email [EMAIL]")
        end
      end

      test "returns input text when sidecar response has unexpected shape" do
        redactor = OpenAiPrivacyFilter.new(client: FakeClient.new([ "not-a-response" ]))

        assert_equal "Email [EMAIL]", redactor.call("Email [EMAIL]")
      end

      test "returns non-string values unchanged" do
        redactor = OpenAiPrivacyFilter.new(client: FakeClient.new({}))

        assert_nil redactor.call(nil)
        assert_equal 42, redactor.call(42)
      end

      test "client posts text to localhost redact endpoint" do
        with_http_response(
          JSON.generate({
            detected_spans: [
              { start: 0, end: 5, label: "private_person" }
            ]
          })
        ) do |endpoint, captured|
          client = OpenAiPrivacyFilter::Client.new(endpoint: endpoint, timeout: 1)

          assert_equal [
            { "start" => 0, "end" => 5, "label" => "private_person" }
          ], client.detect("Alice").fetch("detected_spans")
          assert_equal "/redact", captured.fetch(:path)
          assert_equal({ "text" => "Alice" }, JSON.parse(captured.fetch(:body)))
        end
      end

      test "client raises on non-success response" do
        with_http_response("{}", status: "500 Internal Server Error") do |endpoint, _captured|
          client = OpenAiPrivacyFilter::Client.new(endpoint: endpoint, timeout: 1)

          assert_raises OpenAiPrivacyFilter::ClientError do
            client.detect("Alice")
          end
        end
      end

      test "redactor falls back on invalid JSON response body" do
        with_http_response("not json") do |endpoint, _captured|
          redactor = OpenAiPrivacyFilter.new(endpoint: endpoint, timeout: 1)

          assert_equal "Email [EMAIL]", redactor.call("Email [EMAIL]")
        end
      end

      test "redactor falls back on connection refusal" do
        server = TCPServer.new("127.0.0.1", 0)
        endpoint = "http://127.0.0.1:#{server.addr[1]}"
        server.close
        redactor = OpenAiPrivacyFilter.new(endpoint: endpoint, timeout: 0.1)

        assert_equal "Email [EMAIL]", redactor.call("Email [EMAIL]")
      end

      test "client rejects non-loopback endpoints" do
        assert_raises Tracebook::ConfigurationError do
          OpenAiPrivacyFilter::Client.new(endpoint: "https://example.com/redact", timeout: 1).detect("Alice")
        end
      end

      private

      def with_http_response(body, status: "200 OK")
        captured = {}
        server = TCPServer.new("127.0.0.1", 0)
        endpoint = "http://127.0.0.1:#{server.addr[1]}"
        thread = Thread.new do
          socket = server.accept
          request_line = socket.gets
          captured[:path] = request_line.split[1]
          headers = read_headers(socket)
          captured[:body] = socket.read(headers.fetch("content-length", 0).to_i)
          socket.write http_response(body, status: status)
        ensure
          socket&.close
        end

        yield endpoint, captured
      ensure
        thread&.join
        server&.close
      end

      def read_headers(socket)
        headers = {}
        while (line = socket.gets)
          break if line == "\r\n"

          key, value = line.split(":", 2)
          headers[key.downcase] = value.strip if key && value
        end
        headers
      end

      def http_response(body, status:)
        [
          "HTTP/1.1 #{status}",
          "Content-Type: application/json",
          "Content-Length: #{body.bytesize}",
          "Connection: close",
          "",
          body
        ].join("\r\n")
      end
    end
  end
end
