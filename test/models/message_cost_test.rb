require "test_helper"

module Tracebook
  class MessageCostTest < ActiveSupport::TestCase
    test "validates presence of message_type and message_id" do
      cost = MessageCost.new
      assert_not cost.valid?
      assert_includes cost.errors[:message_type], "can't be blank"
      assert_includes cost.errors[:message_id], "can't be blank"
    end

    test "creates a cost record" do
      cost = MessageCost.create!(
        message_type: "Message",
        message_id: 1,
        cost_input_cents: 10,
        cost_output_cents: 50,
        cost_total_cents: 60,
        currency: "USD",
        latency_ms: 250
      )

      assert_equal 10, cost.cost_input_cents
      assert_equal 50, cost.cost_output_cents
      assert_equal 60, cost.cost_total_cents
      assert_equal 250, cost.latency_ms
    end
  end
end
