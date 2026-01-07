# frozen_string_literal: true

require "active_support/core_ext/object/deep_dup"
require_relative "redaction_audit"

module Tracebook
  # Pipeline for applying PII redaction to LLM interaction data.
  #
  # Supports two interfaces:
  # - New Pattern-based redactors: `call(text, audit:)` returning `[text, audit]`
  # - Legacy lambda redactors: `call(text)` returning `text`
  #
  # The pipeline auto-detects which interface to use based on the callable's
  # arity and provides backwards compatibility for existing custom_redactors.
  #
  # @example Using new Pattern-based redaction
  #   TraceBook.configure do |config|
  #     config.redact :email, :phone
  #   end
  #   pipeline = RedactionPipeline.new
  #   result = pipeline.call(normalized_interaction)
  #   result.redaction_audit.redaction_count  # => 3
  #
  # @example Using legacy lambda redactors
  #   TraceBook.configure do |config|
  #     config.custom_redactors = [
  #       ->(text) { text.gsub(/secret=\w+/, "secret=[REDACTED]") }
  #     ]
  #   end
  #
  class RedactionPipeline
    attr_reader :config

    def initialize(config: Tracebook.config)
      @config = config
    end

    def call(normalized)
      data = normalized.to_h.deep_dup
      @audit = RedactionAudit.new

      apply_pattern_redactors!(data)
      apply_callable_redactors!(data)

      data[:redaction_audit] = @audit
      NormalizedInteraction.new(**data)
    end

    private

    # Apply new-style Pattern redactors from config.active_patterns
    def apply_pattern_redactors!(data)
      patterns = config.respond_to?(:active_patterns) ? config.active_patterns : []
      patterns.each do |pattern|
        apply_pattern_to_request!(data, pattern)
        apply_pattern_to_response!(data, pattern)
        apply_pattern_to_metadata!(data, pattern)
      end
    end

    def apply_pattern_to_request!(data, pattern)
      data[:request_payload], @audit = deep_transform_with_audit(
        data[:request_payload], pattern, "request_payload"
      )
      if data[:request_text].is_a?(String)
        data[:request_text], @audit = pattern.call(
          data[:request_text], audit: @audit, field_path: "request_text"
        )
      end
    end

    def apply_pattern_to_response!(data, pattern)
      data[:response_payload], @audit = deep_transform_with_audit(
        data[:response_payload], pattern, "response_payload"
      )
      if data[:response_text].is_a?(String)
        data[:response_text], @audit = pattern.call(
          data[:response_text], audit: @audit, field_path: "response_text"
        )
      end
    end

    def apply_pattern_to_metadata!(data, pattern)
      data[:metadata], @audit = deep_transform_with_audit(
        data[:metadata], pattern, "metadata"
      )
    end

    def deep_transform_with_audit(value, pattern, path)
      case value
      when String
        pattern.call(value, audit: @audit, field_path: path)
      when Hash
        result = {}
        value.each do |key, nested|
          result[key], @audit = deep_transform_with_audit(nested, pattern, "#{path}.#{key}")
        end
        [ result, @audit ]
      when Array
        result = value.map.with_index do |nested, idx|
          transformed, @audit = deep_transform_with_audit(nested, pattern, "#{path}[#{idx}]")
          transformed
        end
        [ result, @audit ]
      else
        [ value, @audit ]
      end
    end

    # Apply legacy callable redactors (custom_redactors)
    def apply_callable_redactors!(data)
      redactors = Array(config.redactors) + Array(config.custom_redactors)
      redactors.each do |redactor|
        wrapped = wrap_legacy_redactor(redactor)
        apply_wrapped_to_request!(data, wrapped)
        apply_wrapped_to_response!(data, wrapped)
        apply_wrapped_to_metadata!(data, wrapped)
      end
    end

    # Wrap legacy single-arg lambdas to work with audit interface.
    #
    # Detects if the redactor is:
    # - New-style: responds to `call(text, audit:)` (arity -1 with keywords or 2)
    # - Legacy-style: responds to `call(text)` (arity 1)
    #
    # @param redactor [#call] The redactor callable
    # @return [#call] A wrapped callable with consistent interface
    def wrap_legacy_redactor(redactor)
      return redactor if new_style_redactor?(redactor)

      # Wrap legacy lambda to track redactions
      ->(text, audit:, field_path: nil) {
        return [ text, audit ] unless text.is_a?(String)

        result = redactor.call(text)
        updated_audit = audit

        # Track if redaction occurred (text changed)
        if result != text
          redactor_name = extract_redactor_name(redactor)
          updated_audit = audit.record_redaction(redactor_name, field_path || "inline")
        end

        [ result, updated_audit ]
      }
    end

    def new_style_redactor?(redactor)
      # Pattern objects respond to call(text, audit:, field_path:)
      return true if redactor.is_a?(Redactors::Pattern)

      # Check if lambda/proc accepts keyword arguments
      if redactor.respond_to?(:parameters)
        params = redactor.parameters
        params.any? { |type, name| type == :keyreq && name == :audit }
      else
        false
      end
    end

    def extract_redactor_name(redactor)
      if redactor.respond_to?(:name) && redactor.name
        redactor.name
      elsif redactor.is_a?(Proc) && redactor.source_location
        file, line = redactor.source_location
        "lambda@#{File.basename(file)}:#{line}"
      else
        "custom_lambda"
      end
    end

    def apply_wrapped_to_request!(data, redactor)
      data[:request_payload], @audit = deep_transform_with_audit(
        data[:request_payload], redactor, "request_payload"
      )
      if data[:request_text].is_a?(String)
        data[:request_text], @audit = call_redactor(
          redactor, data[:request_text], "request_text"
        )
      end
    end

    def apply_wrapped_to_response!(data, redactor)
      data[:response_payload], @audit = deep_transform_with_audit(
        data[:response_payload], redactor, "response_payload"
      )
      if data[:response_text].is_a?(String)
        data[:response_text], @audit = call_redactor(
          redactor, data[:response_text], "response_text"
        )
      end
    end

    def apply_wrapped_to_metadata!(data, redactor)
      data[:metadata], @audit = deep_transform_with_audit(
        data[:metadata], redactor, "metadata"
      )
    end

    def call_redactor(redactor, text, field_path)
      redactor.call(text, audit: @audit, field_path: field_path)
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
