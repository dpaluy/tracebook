# frozen_string_literal: true

require "active_support/core_ext/object/deep_dup"

module Tracebook
  class RedactionPipeline
    attr_reader :config

    def initialize(config: Tracebook.config)
      @config = config
    end

    def call(normalized)
      data = normalized.to_h.deep_dup

      apply_callable_redactors!(data)
      apply_database_rules!(data)

      NormalizedInteraction.new(**data)
    end

    private

    def apply_callable_redactors!(data)
      redactors = Array(config.redactors) + Array(config.custom_redactors)
      redactors.each do |redactor|
        apply_to_request!(data, redactor)
        apply_to_response!(data, redactor)
        apply_to_metadata!(data, redactor)
      end
    end

    def apply_database_rules!(data)
      Tracebook::RedactionRule.where(enabled: true).order(:priority).find_each do |rule|
        callable = ->(value) { redact_string(value, rule.compiled_pattern, rule.replacement) }

        case rule.applies_to.to_sym
        when :request
          apply_to_request!(data, callable)
        when :response
          apply_to_response!(data, callable)
        when :both
          apply_to_request!(data, callable)
          apply_to_response!(data, callable)
        when :metadata
          apply_to_metadata!(data, callable)
        end
      end
    end

    def apply_to_request!(data, redactor)
      data[:request_payload] = deep_transform(data[:request_payload], redactor)
      data[:request_text] = redactor.call(data[:request_text]) if data[:request_text].is_a?(String)
    end

    def apply_to_response!(data, redactor)
      data[:response_payload] = deep_transform(data[:response_payload], redactor)
      data[:response_text] = redactor.call(data[:response_text]) if data[:response_text].is_a?(String)
    end

    def apply_to_metadata!(data, redactor)
      data[:metadata] = deep_transform(data[:metadata], redactor)
    end

    def deep_transform(value, redactor)
      case value
      when String
        redactor.call(value)
      when Hash
        value.each_with_object({}) do |(key, nested), memo|
          memo[key] = deep_transform(nested, redactor)
        end
      when Array
        value.map { |nested| deep_transform(nested, redactor) }
      else
        value
      end
    end

    def redact_string(value, pattern, replacement)
      return value unless value.is_a?(String)

      value.gsub(pattern, replacement)
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
