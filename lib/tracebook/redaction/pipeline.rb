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
      # @return [String] redacted text
      def call(text)
        return text unless text.is_a?(String)
        return text if patterns.empty? && custom_redactors.empty?

        result = text
        patterns.each { |pattern| result = pattern.redact(result) }
        custom_redactors.each { |redactor| result = redactor.call(result) }
        result
      end

      def active?
        patterns.any? || custom_redactors.any?
      end
    end
  end
end
