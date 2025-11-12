# frozen_string_literal: true

module Tracebook
  module Redactors
    class Base
      def call(value)
        return value unless value.is_a?(String)

        value.gsub(pattern, replacement)
      end

      def applies_to
        :both
      end

      private

      def pattern
        raise NotImplementedError, "implement in subclasses"
      end

      def replacement
        "[REDACTED]"
      end
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
