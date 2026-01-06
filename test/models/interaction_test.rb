# frozen_string_literal: true

require "test_helper"

module TraceBook
  class InteractionTest < ActiveSupport::TestCase
    fixtures "tracebook/interactions"

    test "defines status and review_state enums" do
      assert_equal %w[canceled error success], Interaction.statuses.keys.sort
      assert_equal %w[approved flagged pending], Interaction.review_states.keys.sort
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

    test "by_actor_type scope filters by actor_type" do
      user_interaction = tracebook_interactions(:openai_with_actor)

      results = Interaction.by_actor_type("User")
      assert_includes results, user_interaction
      assert results.all? { |i| i.actor_type == "User" }
    end

    test "by_actor_type scope returns all when type is blank" do
      total_count = Interaction.count

      assert_equal total_count, Interaction.by_actor_type(nil).count
      assert_equal total_count, Interaction.by_actor_type("").count
    end

    test "by_actor_id scope filters by actor_id" do
      user_interaction = tracebook_interactions(:openai_with_actor)

      results = Interaction.by_actor_id(user_interaction.actor_id)
      assert_includes results, user_interaction
      assert results.all? { |i| i.actor_id == user_interaction.actor_id }
    end

    test "by_actor scope filters by both type and id" do
      user_interaction = tracebook_interactions(:openai_with_actor)

      results = Interaction.by_actor("User", 1)
      assert_includes results, user_interaction
      assert_equal 1, results.count
    end

    test "filtered includes actor filters" do
      user_interaction = tracebook_interactions(:openai_with_actor)

      results = Interaction.filtered(actor_type: "User", actor_id: 1)
      assert_includes results, user_interaction
    end

    test "auto-generates session_id when not provided" do
      interaction = Interaction.create!(provider: "openai", model: "gpt-4")
      assert interaction.session_id.present?
      assert interaction.session_id.start_with?("tb_")
    end

    test "preserves session_id when provided" do
      interaction = Interaction.create!(provider: "openai", model: "gpt-4", session_id: "my-session")
      assert_equal "my-session", interaction.session_id
    end

    test "context_label returns metadata context_label when present" do
      interaction = Interaction.new(metadata: { "context_label" => "Form #123 filling" })
      assert_equal "Form #123 filling", interaction.context_label
    end

    test "context_label falls back to truncated session_id" do
      interaction = Interaction.new(session_id: "tb_abc123def456ghi789")
      assert_equal "tb_abc123def456gh...", interaction.context_label
    end
  end
end
