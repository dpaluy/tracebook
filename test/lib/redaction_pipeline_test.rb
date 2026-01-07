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

    # T8: Legacy lambda wrapper tests

    test "legacy lambdas track redactions in audit" do
      TraceBook.configure do |config|
        config.custom_redactors = [
          ->(text) { text.gsub(/secret/, "[REDACTED]") }
        ]
      end

      normalized = NormalizedInteraction.new(
        provider: "openai",
        model: "gpt-4o",
        request_payload: {},
        response_payload: {},
        request_text: "my secret data",
        response_text: "another secret here"
      )

      pipeline = RedactionPipeline.new(config: TraceBook.config)
      redacted = pipeline.call(normalized)

      assert_equal "my [REDACTED] data", redacted.request_text
      assert_equal "another [REDACTED] here", redacted.response_text
      assert_kind_of Tracebook::RedactionAudit, redacted.redaction_audit
      assert redacted.redaction_audit.redaction_count >= 2
    end

    test "pattern-based redactors work with audit tracking" do
      TraceBook.configure do |config|
        config.redact :email
      end

      normalized = NormalizedInteraction.new(
        provider: "openai",
        model: "gpt-4o",
        request_payload: { "contact" => "user@example.com" },
        response_payload: {},
        request_text: "Email: admin@test.org",
        response_text: "OK"
      )

      pipeline = RedactionPipeline.new(config: TraceBook.config)
      redacted = pipeline.call(normalized)

      assert_equal "Email: [EMAIL]", redacted.request_text
      assert_equal "[EMAIL]", redacted.request_payload["contact"]
      assert_equal 2, redacted.redaction_audit.redaction_count
      assert redacted.redaction_audit.redactors_applied.include?("email")
    end

    test "combines pattern redactors with legacy lambdas" do
      TraceBook.configure do |config|
        config.redact :email
        config.custom_redactors = [
          ->(text) { text.gsub(/secret=\w+/, "secret=[HIDDEN]") }
        ]
      end

      normalized = NormalizedInteraction.new(
        provider: "openai",
        model: "gpt-4o",
        request_payload: {},
        response_payload: {},
        request_text: "user@example.com secret=abc123",
        response_text: "Done"
      )

      pipeline = RedactionPipeline.new(config: TraceBook.config)
      redacted = pipeline.call(normalized)

      assert_equal "[EMAIL] secret=[HIDDEN]", redacted.request_text
      assert redacted.redaction_audit.redaction_count >= 2
    end

    test "new-style redactor with audit keyword is not wrapped" do
      new_style_redactor = ->(text, audit:, field_path: nil) {
        result = text.gsub(/token=\w+/, "[TOKEN]")
        updated_audit = result != text ? audit.record_redaction("token", field_path) : audit
        [ result, updated_audit ]
      }

      TraceBook.configure do |config|
        config.custom_redactors = [ new_style_redactor ]
      end

      normalized = NormalizedInteraction.new(
        provider: "openai",
        model: "gpt-4o",
        request_payload: {},
        response_payload: {},
        request_text: "token=xyz789",
        response_text: "OK"
      )

      pipeline = RedactionPipeline.new(config: TraceBook.config)
      redacted = pipeline.call(normalized)

      assert_equal "[TOKEN]", redacted.request_text
      assert_equal 1, redacted.redaction_audit.redaction_count
      assert redacted.redaction_audit.redactors_applied.include?("token")
    end

    test "legacy lambda that does not change text does not record redaction" do
      TraceBook.configure do |config|
        config.custom_redactors = [
          ->(text) { text.gsub(/nonexistent/, "[REDACTED]") }
        ]
      end

      normalized = NormalizedInteraction.new(
        provider: "openai",
        model: "gpt-4o",
        request_payload: {},
        response_payload: {},
        request_text: "nothing to redact",
        response_text: "OK"
      )

      pipeline = RedactionPipeline.new(config: TraceBook.config)
      redacted = pipeline.call(normalized)

      assert_equal "nothing to redact", redacted.request_text
      assert_equal 0, redacted.redaction_audit.redaction_count
    end

    test "returns redaction_audit on result" do
      normalized = NormalizedInteraction.new(
        provider: "openai",
        model: "gpt-4o",
        request_payload: {},
        response_payload: {},
        request_text: "test",
        response_text: "OK"
      )

      pipeline = RedactionPipeline.new(config: TraceBook.config)
      redacted = pipeline.call(normalized)

      assert_not_nil redacted.redaction_audit
      assert_kind_of Tracebook::RedactionAudit, redacted.redaction_audit
    end

    test "redacts nested arrays and hashes" do
      TraceBook.configure do |config|
        config.redact :email
      end

      normalized = NormalizedInteraction.new(
        provider: "openai",
        model: "gpt-4o",
        request_payload: {
          "users" => [
            { "email" => "a@example.com" },
            { "email" => "b@example.org" }
          ]
        },
        response_payload: {},
        request_text: "",
        response_text: ""
      )

      pipeline = RedactionPipeline.new(config: TraceBook.config)
      redacted = pipeline.call(normalized)

      assert_equal "[EMAIL]", redacted.request_payload["users"][0]["email"]
      assert_equal "[EMAIL]", redacted.request_payload["users"][1]["email"]
      assert_equal 2, redacted.redaction_audit.redaction_count
    end
  end
end
