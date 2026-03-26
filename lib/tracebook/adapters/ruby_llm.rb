# frozen_string_literal: true

module Tracebook
  module Adapters
    module RubyLLM
      def self.enable!
        unless defined?(::RubyLLM)
          raise LoadError, "RubyLLM is not loaded. Add `gem 'ruby_llm'` to your Gemfile."
        end

        message_class = Tracebook.config.message_class.constantize
        message_class.include(CostTracking)
      end

      module CostTracking
        extend ActiveSupport::Concern

        included do
          after_create_commit :tracebook_calculate_cost, if: :assistant?
        end

        private

        def tracebook_calculate_cost
          model_id = chat.model_id
          provider = ::RubyLLM::Models.find(model_id).provider

          Tracebook.calculate_cost!(self, provider: provider, model: model_id)
        rescue StandardError => e
          Rails.logger.error("[Tracebook] Cost calculation failed for message #{id}: #{e.class} - #{e.message}")
        end
      end
    end
  end
end
