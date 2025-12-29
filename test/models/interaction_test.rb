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

    test "by_trackable_type scope filters by trackable_type" do
      Interaction.create!(provider: "openai", model: "gpt-4", trackable_type: "User", trackable_id: 1)
      Interaction.create!(provider: "openai", model: "gpt-4", trackable_type: "Project", trackable_id: 2)

      results = Interaction.by_trackable_type("User")
      assert_equal 1, results.count
      assert_equal "User", results.first.trackable_type
    end

    test "by_trackable_type scope returns all when type is blank" do
      Interaction.create!(provider: "openai", model: "gpt-4", trackable_type: "User", trackable_id: 1)
      Interaction.create!(provider: "openai", model: "gpt-4", trackable_type: "Project", trackable_id: 2)

      assert_equal 2, Interaction.by_trackable_type(nil).count
      assert_equal 2, Interaction.by_trackable_type("").count
    end

    test "by_trackable_id scope filters by trackable_id" do
      Interaction.create!(provider: "openai", model: "gpt-4", trackable_type: "User", trackable_id: 1)
      Interaction.create!(provider: "openai", model: "gpt-4", trackable_type: "User", trackable_id: 2)

      results = Interaction.by_trackable_id(1)
      assert_equal 1, results.count
      assert_equal 1, results.first.trackable_id
    end

    test "by_trackable scope filters by both type and id" do
      Interaction.create!(provider: "openai", model: "gpt-4", trackable_type: "User", trackable_id: 1)
      Interaction.create!(provider: "openai", model: "gpt-4", trackable_type: "User", trackable_id: 2)
      Interaction.create!(provider: "openai", model: "gpt-4", trackable_type: "Project", trackable_id: 1)

      results = Interaction.by_trackable("User", 1)
      assert_equal 1, results.count
      assert_equal "User", results.first.trackable_type
      assert_equal 1, results.first.trackable_id
    end

    test "filtered includes trackable filters" do
      Interaction.create!(provider: "openai", model: "gpt-4", trackable_type: "User", trackable_id: 1)
      Interaction.create!(provider: "openai", model: "gpt-4", trackable_type: "Project", trackable_id: 2)

      results = Interaction.filtered(trackable_type: "User", trackable_id: 1)
      assert_equal 1, results.count
    end
  end
end
