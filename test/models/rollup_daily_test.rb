require "test_helper"

module TraceBook
  class RollupDailyTest < ActiveSupport::TestCase
    test "defaults counters to zero" do
      rollup = RollupDaily.new(date: Date.current)

      assert_equal 0, rollup.interactions_count
      assert_equal 0, rollup.success_count
      assert_equal 0, rollup.error_count
      assert_equal 0, rollup.input_tokens_sum
      assert_equal 0, rollup.output_tokens_sum
      assert_equal 0, rollup.cost_cents_sum
    end
  end
end
