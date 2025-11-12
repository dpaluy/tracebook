require "test_helper"

module TraceBook
  class DailyRollupsJobTest < ActiveSupport::TestCase
    setup do
      Interaction.delete_all
      RollupDaily.delete_all
    end

    test "aggregates metrics for the given day" do
      timestamp = Time.utc(2024, 5, 1, 12, 0, 0)

      Interaction.create!(
        provider: "openai",
        model: "gpt-4o",
        project: "demo",
        status: :success,
        review_state: :pending,
        input_tokens: 100,
        output_tokens: 50,
        total_tokens: 150,
        cost_input_cents: 40,
        cost_output_cents: 60,
        cost_total_cents: 100,
        currency: "USD",
        created_at: timestamp,
        updated_at: timestamp
      )

      Interaction.create!(
        provider: "openai",
        model: "gpt-4o",
        project: "demo",
        status: :error,
        review_state: :flagged,
        input_tokens: 60,
        output_tokens: 40,
        total_tokens: 100,
        cost_input_cents: 0,
        cost_output_cents: 0,
        cost_total_cents: 0,
        currency: "USD",
        created_at: timestamp,
        updated_at: timestamp
      )

      DailyRollupsJob.perform_now(date: Date.new(2024, 5, 1), provider: "openai", model: "gpt-4o", project: "demo")

      rollup = RollupDaily.find_by(date: Date.new(2024, 5, 1), provider: "openai", model: "gpt-4o", project: "demo")
      assert_not_nil rollup
      assert_equal 2, rollup.interactions_count
      assert_equal 1, rollup.success_count
      assert_equal 1, rollup.error_count
      assert_equal 160, rollup.input_tokens_sum
      assert_equal 90, rollup.output_tokens_sum
      assert_equal 100, rollup.cost_cents_sum
    end
  end
end
