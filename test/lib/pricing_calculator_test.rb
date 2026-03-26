require "test_helper"

module TraceBook
  class PricingCalculatorTest < ActiveSupport::TestCase
    setup do
      PricingRule.delete_all
    end

    test "calculates costs using matching rule" do
      # 150 cents per 1M input, 600 cents per 1M output
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
        input_tokens: 1_000_000,
        output_tokens: 1_000_000,
        occurred_at: Time.utc(2024, 5, 1)
      )

      # 1M tokens * 150 cents/1M = 150 cents
      assert_equal 150, cost.input_cents
      assert_equal 600, cost.output_cents
      assert_equal 750, cost.total_cents
    end

    test "calculates fractional cents for small token counts" do
      # $2.50/1M = 250 cents/1M
      PricingRule.create!(
        provider: "openai",
        model_glob: "gpt-4o",
        input_cents_per_unit: 250,
        output_cents_per_unit: 1000,
        effective_from: Date.new(2024, 1, 1)
      )

      cost = Pricing::Calculator.call(
        provider: "openai",
        model: "gpt-4o",
        input_tokens: 1000,
        output_tokens: 500,
        occurred_at: Time.utc(2024, 5, 1)
      )

      # 1000 * 250 / 1M = 0.25 cents
      assert_equal 0.25, cost.input_cents
      # 500 * 1000 / 1M = 0.5 cents
      assert_equal 0.5, cost.output_cents
      assert_equal 0.75, cost.total_cents
    end

    test "prefers more specific glob over broader match" do
      PricingRule.create!(
        provider: "xai",
        model_glob: "grok-4*",
        input_cents_per_unit: 200,
        output_cents_per_unit: 600,
        effective_from: Date.new(2025, 3, 1)
      )
      PricingRule.create!(
        provider: "xai",
        model_glob: "grok-4-1-fast*",
        input_cents_per_unit: 20,
        output_cents_per_unit: 50,
        effective_from: Date.new(2025, 7, 1)
      )

      cost = Pricing::Calculator.call(
        provider: "xai",
        model: "grok-4-1-fast-non-reasoning",
        input_tokens: 1_000_000,
        output_tokens: 1_000_000,
        occurred_at: Time.utc(2025, 8, 1)
      )

      assert_equal 20, cost.input_cents
      assert_equal 50, cost.output_cents
    end

    test "prefers most recent effective_from when specificity is equal" do
      PricingRule.create!(
        provider: "openai",
        model_glob: "gpt-4o",
        input_cents_per_unit: 500,
        output_cents_per_unit: 1500,
        effective_from: Date.new(2024, 1, 1)
      )
      PricingRule.create!(
        provider: "openai",
        model_glob: "gpt-4o",
        input_cents_per_unit: 250,
        output_cents_per_unit: 1000,
        effective_from: Date.new(2024, 8, 1)
      )

      cost = Pricing::Calculator.call(
        provider: "openai",
        model: "gpt-4o",
        input_tokens: 1_000_000,
        output_tokens: 1_000_000,
        occurred_at: Time.utc(2024, 9, 1)
      )

      assert_equal 250, cost.input_cents
      assert_equal 1000, cost.output_cents
    end

    test "handles fractional cents_per_unit for cheap models" do
      # Kimi K2.5: $0.45/1M input = 45 cents/1M, $2.10/1M output = 210 cents/1M
      PricingRule.create!(
        provider: "openrouter",
        model_glob: "kimi-k2.5*",
        input_cents_per_unit: 45,
        output_cents_per_unit: 210,
        effective_from: Date.new(2025, 1, 1)
      )

      cost = Pricing::Calculator.call(
        provider: "openrouter",
        model: "kimi-k2.5",
        input_tokens: 10_000,
        output_tokens: 5_000,
        occurred_at: Time.utc(2025, 6, 1)
      )

      # 10_000 * 45 / 1_000_000 = 0.45 cents
      assert_equal 0.45, cost.input_cents
      # 5_000 * 210 / 1_000_000 = 1.05 cents
      assert_equal 1.05, cost.output_cents
      assert_equal 1.5, cost.total_cents
    end

    test "handles sub-integer cents_per_unit values" do
      # A model priced at $0.00045/1K = 0.045 cents/1K = 4.5 cents/1M
      PricingRule.create!(
        provider: "openrouter",
        model_glob: "cheap-model*",
        input_cents_per_unit: 4.5,
        output_cents_per_unit: 18.5,
        effective_from: Date.new(2025, 1, 1)
      )

      cost = Pricing::Calculator.call(
        provider: "openrouter",
        model: "cheap-model-v1",
        input_tokens: 1_000_000,
        output_tokens: 1_000_000,
        occurred_at: Time.utc(2025, 6, 1)
      )

      assert_equal 4.5, cost.input_cents
      assert_equal 18.5, cost.output_cents
      assert_equal 23.0, cost.total_cents
    end

    test "cost_for handles nil cents_per_unit gracefully" do
      assert_equal 0, Pricing::Calculator.cost_for(nil, 1000)
    end

    test "cost_for handles string cents_per_unit" do
      # "250" as a string (e.g., from a form input or JSON)
      assert_equal 0.25, Pricing::Calculator.cost_for("250", 1000)
    end

    test "cost_for handles zero string" do
      assert_equal 0, Pricing::Calculator.cost_for("0", 1000)
      assert_equal 0, Pricing::Calculator.cost_for("0.0", 1000)
    end

    test "cost_for handles negative values" do
      assert_equal 0, Pricing::Calculator.cost_for(-100, 1000)
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
