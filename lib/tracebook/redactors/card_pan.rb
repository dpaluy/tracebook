# frozen_string_literal: true

module Tracebook
  module Redactors
    class CardPAN < Base
      private

      def pattern
        /\b(?:\d[ -]*?){13,16}\b/
      end
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
