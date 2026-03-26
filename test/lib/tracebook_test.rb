# frozen_string_literal: true

require "test_helper"

class TracebookTest < ActiveSupport::TestCase
  include TracebookTestHostApp

  setup do
    clear_tracebook_test_data!
    configure_tracebook_test_host!
  end

  teardown do
    TraceBook.reset_configuration!
  end

  test "calculate_cost! uses the message timestamp for pricing" do
    message_time = 1.year.ago.change(usec: 0)

    # Old rule: 100 cents/1M input, 200 cents/1M output (effective 2 years ago)
    Tracebook::PricingRule.create!(
      provider: "openai",
      model_glob: "gpt-4o",
      input_cents_per_unit: 100,
      output_cents_per_unit: 200,
      effective_from: 2.years.ago.to_date
    )
    # New rule: 300 cents/1M input, 400 cents/1M output (effective yesterday — after message_time)
    Tracebook::PricingRule.create!(
      provider: "openai",
      model_glob: "gpt-4o",
      input_cents_per_unit: 300,
      output_cents_per_unit: 400,
      effective_from: 1.day.ago.to_date
    )

    chat = TracebookTestChat.create!(created_at: message_time, updated_at: message_time)
    message = TracebookTestMessage.create!(
      chat: chat,
      role: "assistant",
      content: "Hi",
      input_tokens: 1_000_000,
      output_tokens: 1_000_000,
      created_at: message_time,
      updated_at: message_time
    )

    cost = Tracebook.calculate_cost!(message, provider: "openai", model: "gpt-4o")

    # Should use old rule (100/200) since message_time is before new rule's effective_from
    assert_equal 100, cost.cost_input_cents
    assert_equal 200, cost.cost_output_cents
    assert_equal 300, cost.cost_total_cents
  end
end
