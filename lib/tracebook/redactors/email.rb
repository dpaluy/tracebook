# frozen_string_literal: true

module Tracebook
  module Redactors
    class Email < Base
      private

      def pattern
        /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i
      end
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
