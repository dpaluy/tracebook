require "test_helper"

module TraceBook
  class RedactionPipelineTest < ActiveSupport::TestCase
    setup do
      TraceBook.reset_configuration!
      RedactionRule.delete_all
    end

    teardown do
      RedactionRule.delete_all
      TraceBook.reset_configuration!
    end

    test "applies built-in redactors to request and response payloads" do
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

      assert_equal "Contact [REDACTED]", redacted.request_text
      assert_equal "Phone: [REDACTED]", redacted.response_text
      assert_equal "[REDACTED]", redacted.request_payload["user"]["email"]
      assert_equal "[REDACTED]", redacted.request_payload["phone"]
      assert_equal "Call me at [REDACTED]", redacted.response_payload["message"]
    end

    test "applies database redaction rules with priority" do
      RedactionRule.create!(name: "session", pattern: "session-[0-9]+", applies_to: :metadata, priority: 1)

      normalized = NormalizedInteraction.new(
        provider: "openai",
        model: "gpt-4o",
        metadata: { "session" => "session-12345", "notes" => "contains session-67890" }
      )

      pipeline = RedactionPipeline.new(config: TraceBook.config)
      redacted = pipeline.call(normalized)

      assert_equal "[REDACTED]", redacted.metadata["session"]
      assert_equal "contains [REDACTED]", redacted.metadata["notes"]
    end
  end
end
