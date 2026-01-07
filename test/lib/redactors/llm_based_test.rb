require "test_helper"

module Tracebook
  module Redactors
    class LLMBasedTest < ActiveSupport::TestCase
      # Mock LLM client for testing
      class MockClient
        attr_accessor :response, :should_fail, :request_log

        def initialize
          @response = nil
          @should_fail = false
          @request_log = []
        end

        def chat(model:, messages:, timeout:)
          @request_log << { model: model, messages: messages, timeout: timeout }
          raise "Mock LLM error" if should_fail

          response
        end
      end

      setup do
        @mock_client = MockClient.new
      end

      # Initialization tests

      test "initializes with valid parameters" do
        redactor = LLMBased.new(provider: :openai, model: "gpt-4o-mini")

        assert_equal :openai, redactor.provider
        assert_equal "gpt-4o-mini", redactor.model
        assert_equal :sync, redactor.mode
        assert_equal :log_and_continue, redactor.on_failure
        assert_equal 30, redactor.timeout
      end

      test "raises on invalid provider" do
        error = assert_raises(ArgumentError) do
          LLMBased.new(provider: :invalid, model: "model")
        end

        assert_includes error.message, "Unknown provider: invalid"
        assert_includes error.message, "openai"
      end

      test "raises on invalid mode" do
        error = assert_raises(ArgumentError) do
          LLMBased.new(provider: :openai, model: "model", mode: :invalid)
        end

        assert_includes error.message, "Unknown mode: invalid"
      end

      test "raises on invalid on_failure" do
        error = assert_raises(ArgumentError) do
          LLMBased.new(provider: :openai, model: "model", on_failure: :invalid)
        end

        assert_includes error.message, "Unknown on_failure: invalid"
      end

      test "accepts custom prompt" do
        redactor = LLMBased.new(
          provider: :openai,
          model: "gpt-4o-mini",
          prompt: "Custom prompt"
        )

        assert_equal "Custom prompt", redactor.prompt
      end

      # Mode tests

      test "sync? returns true when mode is sync" do
        redactor = LLMBased.new(provider: :openai, model: "model", mode: :sync)
        assert redactor.sync?
        assert_not redactor.async?
      end

      test "async? returns true when mode is async" do
        redactor = LLMBased.new(provider: :openai, model: "model", mode: :async)
        assert redactor.async?
        assert_not redactor.sync?
      end

      # Guard protection tests

      test "guard prevents infinite recursion" do
        redactor = LLMBased.new(provider: :openai, model: "gpt-4o-mini")
        redactor.instance_variable_set(:@client, @mock_client)
        @mock_client.response = openai_response("Redacted text")

        # First call should work
        ActiveSupport::IsolatedExecutionState[LLMBased::GUARD_KEY] = false
        result1, = redactor.call("Some PII text here")

        # Simulate nested call (guard should prevent)
        ActiveSupport::IsolatedExecutionState[LLMBased::GUARD_KEY] = true
        result2, = redactor.call("Another PII text")

        assert_equal "Redacted text", result1
        assert_equal "Another PII text", result2 # Unchanged due to guard
      ensure
        ActiveSupport::IsolatedExecutionState[LLMBased::GUARD_KEY] = false
      end

      test "guard is cleared after successful call" do
        redactor = LLMBased.new(provider: :openai, model: "gpt-4o-mini")
        redactor.instance_variable_set(:@client, @mock_client)
        @mock_client.response = openai_response("Redacted")

        redactor.call("Some text here")

        assert_not ActiveSupport::IsolatedExecutionState[LLMBased::GUARD_KEY]
      end

      test "guard is cleared after failed call" do
        redactor = LLMBased.new(provider: :openai, model: "gpt-4o-mini", on_failure: :log_and_continue)
        redactor.instance_variable_set(:@client, @mock_client)
        @mock_client.should_fail = true

        redactor.call("Some text here")

        assert_not ActiveSupport::IsolatedExecutionState[LLMBased::GUARD_KEY]
      end

      # Redaction tests

      test "redacts text via LLM" do
        redactor = LLMBased.new(provider: :openai, model: "gpt-4o-mini")
        redactor.instance_variable_set(:@client, @mock_client)
        @mock_client.response = openai_response("Hello [NAME], how are you?")

        result, audit = redactor.call("Hello John Smith, how are you?")

        assert_equal "Hello [NAME], how are you?", result
        assert_equal 1, audit.redaction_count
        assert_includes audit.redactors_applied, "llm_based"
      end

      test "returns original text when no changes" do
        redactor = LLMBased.new(provider: :openai, model: "gpt-4o-mini")
        redactor.instance_variable_set(:@client, @mock_client)
        @mock_client.response = openai_response("No PII here")

        result, audit = redactor.call("No PII here")

        assert_equal "No PII here", result
        assert_equal 0, audit.redaction_count
      end

      test "skips very short strings" do
        redactor = LLMBased.new(provider: :openai, model: "gpt-4o-mini")
        redactor.instance_variable_set(:@client, @mock_client)

        result, = redactor.call("Hi")

        assert_equal "Hi", result
        assert_empty @mock_client.request_log # No LLM call made
      end

      test "skips non-string input" do
        redactor = LLMBased.new(provider: :openai, model: "gpt-4o-mini")
        redactor.instance_variable_set(:@client, @mock_client)

        result, = redactor.call(12345)

        assert_equal 12345, result
        assert_empty @mock_client.request_log
      end

      # Audit tracking tests

      test "records redaction in audit with field_path" do
        redactor = LLMBased.new(provider: :openai, model: "gpt-4o-mini")
        redactor.instance_variable_set(:@client, @mock_client)
        @mock_client.response = openai_response("[NAME] lives at [ADDRESS]")

        _, audit = redactor.call("John lives at 123 Main St", field_path: "messages.0.content")

        assert_equal 1, audit.redaction_count
        assert_includes audit.redactors_applied, "llm_based"
      end

      # Failure handling tests

      test "on_failure :log_and_continue returns original text" do
        redactor = LLMBased.new(
          provider: :openai,
          model: "gpt-4o-mini",
          on_failure: :log_and_continue
        )
        redactor.instance_variable_set(:@client, @mock_client)
        @mock_client.should_fail = true

        result, audit = redactor.call("John Smith secret data")

        assert_equal "John Smith secret data", result
        assert audit.redactors_applied.any? { |r| r.include?("llm_based_failure") }
      end

      test "on_failure :raise re-raises exception" do
        redactor = LLMBased.new(
          provider: :openai,
          model: "gpt-4o-mini",
          on_failure: :raise
        )
        redactor.instance_variable_set(:@client, @mock_client)
        @mock_client.should_fail = true

        assert_raises(RuntimeError) do
          redactor.call("Some text here")
        end
      end

      test "on_failure :retry_async returns original text" do
        redactor = LLMBased.new(
          provider: :openai,
          model: "gpt-4o-mini",
          on_failure: :retry_async
        )
        redactor.instance_variable_set(:@client, @mock_client)
        @mock_client.should_fail = true

        result, audit = redactor.call("John Smith data")

        assert_equal "John Smith data", result
        assert audit.redactors_applied.any? { |r| r.include?("llm_based_failure") }
      end

      # Provider abstraction tests

      test "extracts openai response format" do
        redactor = LLMBased.new(provider: :openai, model: "gpt-4o-mini")
        redactor.instance_variable_set(:@client, @mock_client)
        @mock_client.response = openai_response("Redacted OpenAI")

        result, = redactor.call("Original text here")

        assert_equal "Redacted OpenAI", result
      end

      test "extracts anthropic response format" do
        redactor = LLMBased.new(provider: :anthropic, model: "claude-3-haiku")
        redactor.instance_variable_set(:@client, @mock_client)
        @mock_client.response = anthropic_response("Redacted Anthropic")

        result, = redactor.call("Original text here")

        assert_equal "Redacted Anthropic", result
      end

      test "extracts ollama response format" do
        redactor = LLMBased.new(provider: :ollama, model: "llama3.2")
        redactor.instance_variable_set(:@client, @mock_client)
        @mock_client.response = ollama_response("Redacted Ollama")

        result, = redactor.call("Original text here")

        assert_equal "Redacted Ollama", result
      end

      # System prompt tests

      test "uses default prompt when prompt is :default" do
        redactor = LLMBased.new(provider: :openai, model: "gpt-4o-mini")
        redactor.instance_variable_set(:@client, @mock_client)
        @mock_client.response = openai_response("Redacted")

        redactor.call("Some PII text")

        messages = @mock_client.request_log.first[:messages]
        system_message = messages.find { |m| m[:role] == "system" }

        assert_includes system_message[:content], "PII redaction assistant"
        assert_includes system_message[:content], "[NAME]"
      end

      test "uses custom prompt when provided" do
        redactor = LLMBased.new(
          provider: :openai,
          model: "gpt-4o-mini",
          prompt: "Custom redaction rules"
        )
        redactor.instance_variable_set(:@client, @mock_client)
        @mock_client.response = openai_response("Redacted")

        redactor.call("Some PII text")

        messages = @mock_client.request_log.first[:messages]
        system_message = messages.find { |m| m[:role] == "system" }

        assert_equal "Custom redaction rules", system_message[:content]
      end

      private

      def openai_response(content)
        { "choices" => [{ "message" => { "content" => content } }] }
      end

      def anthropic_response(content)
        { "content" => [{ "text" => content }] }
      end

      def ollama_response(content)
        { "message" => { "content" => content } }
      end
    end
  end
end
