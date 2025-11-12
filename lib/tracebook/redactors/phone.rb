# frozen_string_literal: true

module Tracebook
  module Redactors
    class Phone < Base
      private

      def pattern
        /(?:\+?\d{1,3}[\s.-]?)?(?:\(\d{3}\)|\d{3})[\s.-]?\d{3}[\s.-]?\d{4}/
      end
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
