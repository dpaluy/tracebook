# frozen_string_literal: true

module Tracebook
  module Redaction
    class Pipeline
      attr_reader :patterns, :custom_redactors

      def initialize(patterns: [], custom_redactors: [])
        @patterns = patterns
        @custom_redactors = custom_redactors
      end

      # Redact a string through all patterns and custom redactors.
      #
      # @param text [String] the text to redact
      # @param scope [Object, nil] optional conversation/session scope for scope-aware redactors
      # @return [String] redacted text
      def call(text, scope: nil)
        return text unless text.is_a?(String)
        return text if patterns.empty? && custom_redactors.empty?

        result = text
        patterns.each { |pattern| result = pattern.redact(result) }
        custom_redactors.each { |redactor| result = call_redactor(redactor, result, scope) }
        result
      end

      def active?
        patterns.any? || custom_redactors.any?
      end

      private

      def call_redactor(redactor, text, scope)
        return redactor.call(text, scope: scope) if !scope.nil? && accepts_scope_keyword?(redactor)

        redactor.call(text)
      end

      def accepts_scope_keyword?(redactor)
        callable_parameters(redactor).any? do |type, name|
          type == :keyrest || (name == :scope && %i[key keyreq].include?(type))
        end
      end

      def callable_parameters(redactor)
        return redactor.parameters if redactor.respond_to?(:parameters)

        redactor.method(:call).parameters
      end
    end
  end
end
