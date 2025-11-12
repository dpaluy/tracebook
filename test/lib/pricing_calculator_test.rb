require "test_helper"

module TraceBook
  class PricingCalculatorTest < ActiveSupport::TestCase
    setup do
      PricingRule.delete_all
    end

    test "calculates costs using matching rule" do
      PricingRule.create!(
        provider: "openai",
        model_glob: "gpt-*",
        input_cents_per_unit: 150,
        output_cents_per_unit: 600,
        effective_from: Date.new(2024, 1, 1)
      )

      cost = Pricing::Calculator.call(
        provider: "openai",
        model: "gpt-4o",
        input_tokens: 1200,
        output_tokens: 300,
        occurred_at: Time.utc(2024, 5, 1)
      )

      assert_equal 180, cost.input_cents
      assert_equal 180, cost.output_cents
      assert_equal 360, cost.total_cents
    end

    test "falls back to zero cost when no rule" do
      cost = Pricing::Calculator.call(
        provider: "anthropic",
        model: "claude-3",
        input_tokens: 1000,
        output_tokens: 1000,
        occurred_at: Time.utc(2024, 5, 1)
      )

      assert_equal 0, cost.total_cents
    end
  end
end
