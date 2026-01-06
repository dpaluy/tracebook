# frozen_string_literal: true

require "test_helper"

module Tracebook
  module Seeds
    class PricingRulesTest < ActiveSupport::TestCase
      setup do
        PricingRule.delete_all
      end

      test "seeds all default pricing rules" do
        result = PricingRules.seed!

        assert_equal 10, result[:created]
        assert_equal 0, result[:skipped]
        assert_equal 10, PricingRule.count
      end

      test "is idempotent - skips existing rules on second run" do
        PricingRules.seed!
        result = PricingRules.seed!

        assert_equal 0, result[:created]
        assert_equal 10, result[:skipped]
        assert_equal 10, PricingRule.count
      end

      test "seeds all expected providers" do
        PricingRules.seed!

        providers = PricingRule.pluck(:provider).uniq.sort
        assert_equal %w[anthropic gemini ollama openai], providers
      end

      test "seeds correct pricing for gpt-4o" do
        PricingRules.seed!

        rule = PricingRule.find_by(provider: "openai", model_glob: "gpt-4o")
        assert_equal 250, rule.input_cents_per_unit
        assert_equal 1000, rule.output_cents_per_unit
        assert_equal "USD", rule.currency
      end

      test "ollama rules have zero cost" do
        PricingRules.seed!

        rule = PricingRule.find_by(provider: "ollama")
        assert_equal 0, rule.input_cents_per_unit
        assert_equal 0, rule.output_cents_per_unit
      end

      test "all rules have valid effective_from dates" do
        PricingRules.seed!

        PricingRule.find_each do |rule|
          assert rule.effective_from.present?, "#{rule.provider}/#{rule.model_glob} missing effective_from"
          assert rule.effective_from < Date.current, "#{rule.provider}/#{rule.model_glob} has future effective_from"
        end
      end
    end
  end
end
