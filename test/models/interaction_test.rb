require "test_helper"

module TraceBook
  class InteractionTest < ActiveSupport::TestCase
    test "defines status and review_state enums" do
      assert_equal %w[canceled error success], Interaction.statuses.keys.sort
      assert_equal %w[approved flagged pending rejected], Interaction.review_states.keys.sort
    end

    test "defaults review_state to pending" do
      interaction = Interaction.new
      assert_equal "pending", interaction.review_state
    end

    test "validates presence of core attributes" do
      interaction = Interaction.new

      assert_not interaction.valid?
      assert_includes interaction.errors.attribute_names, :provider
      assert_includes interaction.errors.attribute_names, :model
      # status and review_state are enums with defaults, so they're always present
    end
  end
end
