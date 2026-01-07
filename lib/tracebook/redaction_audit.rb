# frozen_string_literal: true

module Tracebook
  # Value object for auditing redaction operations.
  #
  # Tracks what was redacted, when, and by which rules for GDPR/CCPA compliance.
  # Immutable after creation - use builder methods to construct instances.
  #
  # @attr redacted_at [String] ISO8601 timestamp when redaction occurred
  # @attr redactors_applied [Array<String>] List of redactor names that ran (sorted)
  # @attr fields_redacted [Hash<String, Array<String>>] Map of field paths to redactor names
  # @attr redaction_count [Integer] Total number of redactions performed
  # @attr llm_redaction_status [String, nil] "success", "failed", or "skipped"
  # @attr llm_redacted_at [String, nil] ISO8601 timestamp when LLM redaction succeeded
  # @attr llm_redaction_error [String, nil] Error message if LLM redaction failed
  #
  # @example Building and using an audit
  #   audit = RedactionAudit.new
  #   audit = audit.record_redaction("email", "request_payload.messages[0].content")
  #   audit = audit.record_redaction("phone", "response_payload.content")
  #   audit = audit.record_llm_failure("Rate limit exceeded")
  #   audit.to_h  # => { redacted_at: "2026-01-06T12:00:00Z", ... }
  #
  class RedactionAudit
    attr_reader :redacted_at, :redactors_applied, :fields_redacted, :redaction_count,
                :llm_redaction_status, :llm_redacted_at, :llm_redaction_error

    # Initialize a new RedactionAudit with default values.
    #
    # @param redacted_at [String] Timestamp (default: current time in ISO8601)
    # @param redactors_applied [Array<String>] Redactor names (default: empty)
    # @param fields_redacted [Hash<String, Array<String>>] Field map (default: empty)
    # @param redaction_count [Integer] Total redactions (default: 0)
    # @param llm_redaction_status [String, nil] LLM status (default: nil)
    # @param llm_redacted_at [String, nil] LLM success timestamp (default: nil)
    # @param llm_redaction_error [String, nil] LLM error message (default: nil)
    #
    def initialize(
      redacted_at: nil,
      redactors_applied: [],
      fields_redacted: {},
      redaction_count: 0,
      llm_redaction_status: nil,
      llm_redacted_at: nil,
      llm_redaction_error: nil
    )
      @redacted_at = redacted_at || Time.current.iso8601
      @redactors_applied = redactors_applied.dup
      @fields_redacted = fields_redacted.dup
      @redaction_count = redaction_count
      @llm_redaction_status = llm_redaction_status
      @llm_redacted_at = llm_redacted_at
      @llm_redaction_error = llm_redaction_error

      freeze
    end

    # Record a redaction event.
    #
    # Updates the audit trail to reflect that a redactor was applied to a field.
    # Increments the redaction count and adds the redactor name to applied list.
    #
    # @param redactor_name [String] Name of the redactor (e.g., "email", "phone")
    # @param field_path [String] Dot-notation path to the redacted field
    #   (e.g., "request_payload.messages[0].content")
    #
    # @return [RedactionAudit] New audit instance with recorded redaction
    #
    # @example Record multiple redactions
    #   audit = RedactionAudit.new
    #   audit = audit.record_redaction("email", "request_payload.user.email")
    #   audit = audit.record_redaction("phone", "request_payload.contact.phone")
    #   audit = audit.record_redaction("email", "response_payload.from")
    #   # redactors_applied: ["email", "phone"]
    #   # fields_redacted: {
    #   #   "request_payload.user.email" => ["email"],
    #   #   "request_payload.contact.phone" => ["phone"],
    #   #   "response_payload.from" => ["email"]
    #   # }
    #
    def record_redaction(redactor_name, field_path)
      new_redactors = Set.new(redactors_applied)
      new_redactors.add(redactor_name)

      new_fields = fields_redacted.dup
      new_fields[field_path] ||= []
      new_fields[field_path] = (new_fields[field_path] + [redactor_name]).uniq

      RedactionAudit.new(
        redacted_at: redacted_at,
        redactors_applied: new_redactors.to_a.sort,
        fields_redacted: new_fields,
        redaction_count: redaction_count + 1,
        llm_redaction_status: llm_redaction_status,
        llm_redacted_at: llm_redacted_at,
        llm_redaction_error: llm_redaction_error
      )
    end

    # Record an LLM redaction failure.
    #
    # Updates the audit trail to mark LLM-based redaction as failed,
    # storing the error message for debugging.
    #
    # @param error_message [String] Description of the failure
    #
    # @return [RedactionAudit] New audit instance with failure recorded
    #
    # @example Record and handle LLM failure
    #   audit = RedactionAudit.new
    #   audit = audit.record_llm_failure("OpenAI rate limit exceeded")
    #   audit.llm_redaction_status # => "failed"
    #   audit.llm_redaction_error  # => "OpenAI rate limit exceeded"
    #
    def record_llm_failure(error_message)
      RedactionAudit.new(
        redacted_at: redacted_at,
        redactors_applied: redactors_applied,
        fields_redacted: fields_redacted,
        redaction_count: redaction_count,
        llm_redaction_status: "failed",
        llm_redacted_at: llm_redacted_at,
        llm_redaction_error: error_message
      )
    end

    # Record successful LLM redaction.
    #
    # Updates the audit trail to mark LLM-based redaction as successful,
    # storing the completion timestamp.
    #
    # @param at [String] ISO8601 timestamp (default: current time)
    #
    # @return [RedactionAudit] New audit instance with success recorded
    #
    # @example Mark LLM redaction as succeeded
    #   audit = RedactionAudit.new
    #   audit = audit.record_llm_success("2026-01-06T12:05:00Z")
    #   audit.llm_redaction_status # => "success"
    #   audit.llm_redacted_at      # => "2026-01-06T12:05:00Z"
    #
    def record_llm_success(at: nil)
      RedactionAudit.new(
        redacted_at: redacted_at,
        redactors_applied: redactors_applied,
        fields_redacted: fields_redacted,
        redaction_count: redaction_count,
        llm_redaction_status: "success",
        llm_redacted_at: at || Time.current.iso8601,
        llm_redaction_error: llm_redaction_error
      )
    end

    # Record that LLM redaction was skipped.
    #
    # Updates the audit trail to mark LLM-based redaction as skipped
    # (e.g., no LLM redactor configured, or redaction already complete).
    #
    # @return [RedactionAudit] New audit instance with skip recorded
    #
    # @example Mark LLM redaction as skipped
    #   audit = RedactionAudit.new
    #   audit = audit.record_llm_skip
    #   audit.llm_redaction_status # => "skipped"
    #
    def record_llm_skip
      RedactionAudit.new(
        redacted_at: redacted_at,
        redactors_applied: redactors_applied,
        fields_redacted: fields_redacted,
        redaction_count: redaction_count,
        llm_redaction_status: "skipped",
        llm_redacted_at: llm_redacted_at,
        llm_redaction_error: llm_redaction_error
      )
    end

    # Convert audit to a hash suitable for JSON serialization.
    #
    # Filters out nil values to keep the hash minimal. Only includes
    # keys with actual values.
    #
    # @return [Hash<Symbol, Object>] Serializable audit hash
    #
    # @example Serialization
    #   audit = RedactionAudit.new
    #   audit = audit.record_redaction("email", "request_payload.user")
    #   audit.to_h
    #   # => {
    #   #      redacted_at: "2026-01-06T12:00:00Z",
    #   #      redactors_applied: ["email"],
    #   #      fields_redacted: { "request_payload.user" => ["email"] },
    #   #      redaction_count: 1,
    #   #      llm_redaction_status: nil,  # Omitted if nil
    #   #      llm_redacted_at: nil,       # Omitted if nil
    #   #      llm_redaction_error: nil    # Omitted if nil
    #   #    }
    #
    def to_h
      {
        redacted_at: redacted_at,
        redactors_applied: redactors_applied,
        fields_redacted: fields_redacted,
        redaction_count: redaction_count,
        llm_redaction_status: llm_redaction_status,
        llm_redacted_at: llm_redacted_at,
        llm_redaction_error: llm_redaction_error
      }.compact
    end

    # Test equality by comparing all attributes
    def ==(other)
      return false unless other.is_a?(RedactionAudit)

      redacted_at == other.redacted_at &&
        redactors_applied == other.redactors_applied &&
        fields_redacted == other.fields_redacted &&
        redaction_count == other.redaction_count &&
        llm_redaction_status == other.llm_redaction_status &&
        llm_redacted_at == other.llm_redacted_at &&
        llm_redaction_error == other.llm_redaction_error
    end

    alias_method :eql?, :==

    def hash
      [
        redacted_at,
        redactors_applied,
        fields_redacted,
        redaction_count,
        llm_redaction_status,
        llm_redacted_at,
        llm_redaction_error
      ].hash
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
