require "test_helper"

module TraceBook
  class RedactionPipelineTest < ActiveSupport::TestCase
    setup do
      TraceBook.reset_configuration!
    end

    teardown do
      TraceBook.reset_configuration!
    end

    test "applies custom redactors to request and response payloads" do
      TraceBook.configure do |config|
        config.custom_redactors = [
          ->(text) { text.gsub(/user@example\.com/, "[EMAIL]") },
          ->(text) { text.gsub(/\(?\d{3}\)?[- ]?\d{3}[- ]?\d{4}/, "[PHONE]") }
        ]
      end

      normalized = NormalizedInteraction.new(
        provider: "openai",
        model: "gpt-4o",
        project: "demo",
        request_payload: { "user" => { "email" => "user@example.com" }, "phone" => "(555) 123-4567" },
        response_payload: { "message" => "Call me at 555-765-4321" },
        request_text: "Contact user@example.com",
        response_text: "Phone: 555-765-4321",
        metadata: {},
        tags: []
      )

      pipeline = RedactionPipeline.new(config: TraceBook.config)
      redacted = pipeline.call(normalized)

      assert_equal "Contact [EMAIL]", redacted.request_text
      assert_equal "Phone: [PHONE]", redacted.response_text
      assert_equal "[EMAIL]", redacted.request_payload["user"]["email"]
      assert_equal "[PHONE]", redacted.request_payload["phone"]
      assert_equal "Call me at [PHONE]", redacted.response_payload["message"]
    end

    test "passes through data unchanged when no redactors configured" do
      normalized = NormalizedInteraction.new(
        provider: "openai",
        model: "gpt-4o",
        project: "demo",
        request_payload: { "content" => "secret data" },
        response_payload: { "content" => "response data" },
        request_text: "secret data",
        response_text: "response data",
        metadata: { "key" => "value" },
        tags: []
      )

      pipeline = RedactionPipeline.new(config: TraceBook.config)
      redacted = pipeline.call(normalized)

      assert_equal "secret data", redacted.request_text
      assert_equal "response data", redacted.response_text
      assert_equal "secret data", redacted.request_payload["content"]
    end
  end
end
