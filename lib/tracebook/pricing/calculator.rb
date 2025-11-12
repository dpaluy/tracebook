# frozen_string_literal: true

module Tracebook
  module Pricing
    CostBreakdown = Data.define(:input_cents, :output_cents, :total_cents, :currency)

    module Calculator
      extend self

      def call(provider:, model:, input_tokens:, output_tokens:, occurred_at: Time.current)
        rule = matching_rule(provider, model, occurred_at)
        return CostBreakdown.new(input_cents: 0, output_cents: 0, total_cents: 0, currency: Tracebook.config.default_currency) unless rule

        input_cents = cost_for(rule.input_cents_per_unit, input_tokens)
        output_cents = cost_for(rule.output_cents_per_unit, output_tokens)
        CostBreakdown.new(
          input_cents: input_cents,
          output_cents: output_cents,
          total_cents: input_cents + output_cents,
          currency: rule.currency
        )
      end

      def matching_rule(provider, model, occurred_at)
        Tracebook::PricingRule.where(provider: provider).select do |rule|
          rule.matches_model?(model) && rule.active_on?(occurred_at.to_date)
        end.min_by(&:effective_from)
      end

      def cost_for(cents_per_unit, tokens)
        return 0 if cents_per_unit.to_i <= 0 || tokens.to_i <= 0

        (tokens.to_i / 1000.0 * cents_per_unit.to_i).round
      end
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
