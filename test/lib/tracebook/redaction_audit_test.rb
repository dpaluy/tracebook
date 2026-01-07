require "test_helper"

module Tracebook
  class RedactionAuditTest < ActiveSupport::TestCase
    test "initializes with default values" do
      audit = RedactionAudit.new

      assert_not_nil audit.redacted_at
      assert_equal [], audit.redactors_applied
      assert_equal({}, audit.fields_redacted)
      assert_equal 0, audit.redaction_count
      assert_nil audit.llm_redaction_status
      assert_nil audit.llm_redacted_at
      assert_nil audit.llm_redaction_error
    end

    test "uses provided redacted_at timestamp" do
      timestamp = "2026-01-06T10:00:00Z"
      audit = RedactionAudit.new(redacted_at: timestamp)

      assert_equal timestamp, audit.redacted_at
    end

    test "record_redaction tracks first redactor" do
      audit = RedactionAudit.new
      audit = audit.record_redaction("email", "request_payload.user.email")

      assert_equal ["email"], audit.redactors_applied
      assert_equal({"request_payload.user.email" => ["email"]}, audit.fields_redacted)
      assert_equal 1, audit.redaction_count
    end

    test "record_redaction deduplicates redactors in applied list" do
      audit = RedactionAudit.new
      audit = audit.record_redaction("email", "request_payload.field1")
      audit = audit.record_redaction("email", "request_payload.field2")

      assert_equal ["email"], audit.redactors_applied
      assert_equal 2, audit.redaction_count
    end

    test "record_redaction sorts redactors alphabetically" do
      audit = RedactionAudit.new
      audit = audit.record_redaction("phone", "field1")
      audit = audit.record_redaction("email", "field2")
      audit = audit.record_redaction("ssn", "field3")

      assert_equal ["email", "phone", "ssn"], audit.redactors_applied
    end

    test "record_redaction tracks multiple redactors applied to same field" do
      audit = RedactionAudit.new
      audit = audit.record_redaction("email", "request_payload.content")
      audit = audit.record_redaction("phone", "request_payload.content")

      assert_equal({"request_payload.content" => ["email", "phone"]}, audit.fields_redacted)
      assert_equal 2, audit.redaction_count
    end

    test "record_redaction deduplicates redactors per field" do
      audit = RedactionAudit.new
      audit = audit.record_redaction("email", "field1")
      audit = audit.record_redaction("email", "field1")

      assert_equal({"field1" => ["email"]}, audit.fields_redacted)
      assert_equal 2, audit.redaction_count  # Still increments
    end

    test "record_redaction handles nested field paths" do
      audit = RedactionAudit.new
      audit = audit.record_redaction("email", "request_payload.messages[0].content")
      audit = audit.record_redaction("phone", "response_payload.data[1].value")

      assert_equal(
        {
          "request_payload.messages[0].content" => ["email"],
          "response_payload.data[1].value" => ["phone"]
        },
        audit.fields_redacted
      )
    end

    test "record_redaction is immutable" do
      audit1 = RedactionAudit.new
      audit2 = audit1.record_redaction("email", "field1")

      assert_not_equal audit1.object_id, audit2.object_id
      assert_equal 0, audit1.redaction_count
      assert_equal 1, audit2.redaction_count
    end

    test "record_llm_failure sets status and error message" do
      audit = RedactionAudit.new
      audit = audit.record_llm_failure("OpenAI rate limit exceeded")

      assert_equal "failed", audit.llm_redaction_status
      assert_equal "OpenAI rate limit exceeded", audit.llm_redaction_error
      assert_nil audit.llm_redacted_at
    end

    test "record_llm_failure overwrites previous LLM status" do
      audit = RedactionAudit.new(llm_redaction_status: "success")
      audit = audit.record_llm_failure("Connection timeout")

      assert_equal "failed", audit.llm_redaction_status
      assert_equal "Connection timeout", audit.llm_redaction_error
    end

    test "record_llm_success sets status and timestamp" do
      audit = RedactionAudit.new
      timestamp = "2026-01-06T12:05:00Z"
      audit = audit.record_llm_success(at: timestamp)

      assert_equal "success", audit.llm_redaction_status
      assert_equal timestamp, audit.llm_redacted_at
      assert_nil audit.llm_redaction_error
    end

    test "record_llm_success uses current time by default" do
      audit = RedactionAudit.new
      before = Time.current.iso8601
      audit = audit.record_llm_success
      after = Time.current.iso8601

      assert_equal "success", audit.llm_redaction_status
      assert audit.llm_redacted_at >= before
      assert audit.llm_redacted_at <= after
    end

    test "record_llm_skip sets status to skipped" do
      audit = RedactionAudit.new
      audit = audit.record_llm_skip

      assert_equal "skipped", audit.llm_redaction_status
      assert_nil audit.llm_redacted_at
      assert_nil audit.llm_redaction_error
    end

    test "record_llm_skip clears previous LLM status" do
      audit = RedactionAudit.new(llm_redaction_status: "failed", llm_redaction_error: "Error")
      audit = audit.record_llm_skip

      assert_equal "skipped", audit.llm_redaction_status
      # error message is still there (we only clear status)
      assert_equal "Error", audit.llm_redaction_error
    end

    test "to_h returns compact hash without nil values" do
      audit = RedactionAudit.new(redacted_at: "2026-01-06T12:00:00Z")
      hash = audit.to_h

      refute_includes hash, :llm_redaction_status
      refute_includes hash, :llm_redacted_at
      refute_includes hash, :llm_redaction_error
      assert_includes hash, :redacted_at
      assert_includes hash, :redaction_count
    end

    test "to_h includes non-nil values" do
      audit = RedactionAudit.new
      audit = audit.record_redaction("email", "field1")
      audit = audit.record_llm_failure("Error message")

      hash = audit.to_h

      assert_equal ["email"], hash[:redactors_applied]
      assert_equal({"field1" => ["email"]}, hash[:fields_redacted])
      assert_equal 1, hash[:redaction_count]
      assert_equal "failed", hash[:llm_redaction_status]
      assert_equal "Error message", hash[:llm_redaction_error]
    end

    test "to_h with complex nested redactions" do
      audit = RedactionAudit.new
      audit = audit.record_redaction("email", "request.messages[0].content")
      audit = audit.record_redaction("phone", "request.messages[0].content")
      audit = audit.record_redaction("ssn", "response.pii[1]")

      hash = audit.to_h

      assert_equal ["email", "phone", "ssn"], hash[:redactors_applied]
      assert_equal(
        {
          "request.messages[0].content" => ["email", "phone"],
          "response.pii[1]" => ["ssn"]
        },
        hash[:fields_redacted]
      )
      assert_equal 3, hash[:redaction_count]
    end

    test "chaining operations preserves previous state" do
      audit = RedactionAudit.new
      audit = audit.record_redaction("email", "field1")
      audit = audit.record_redaction("phone", "field2")
      audit = audit.record_llm_failure("Timeout")

      hash = audit.to_h

      assert_equal ["email", "phone"], hash[:redactors_applied]
      assert_equal 2, hash[:redaction_count]
      assert_equal "failed", hash[:llm_redaction_status]
      assert_equal "Timeout", hash[:llm_redaction_error]
    end

    test "empty fields_redacted when no redactions recorded" do
      audit = RedactionAudit.new
      hash = audit.to_h

      assert_equal({}, hash[:fields_redacted])
    end

    test "redactors_applied remains sorted through mutations" do
      audit = RedactionAudit.new
      audit = audit.record_redaction("zzz", "field1")
      audit = audit.record_redaction("aaa", "field2")
      audit = audit.record_redaction("mmm", "field3")

      assert_equal ["aaa", "mmm", "zzz"], audit.redactors_applied
    end

    test "redaction_count increments even for duplicate field-redactor pairs" do
      audit = RedactionAudit.new
      audit = audit.record_redaction("email", "field1")
      audit = audit.record_redaction("email", "field1")
      audit = audit.record_redaction("email", "field1")

      assert_equal 3, audit.redaction_count
      assert_equal({"field1" => ["email"]}, audit.fields_redacted)
    end
  end
end
