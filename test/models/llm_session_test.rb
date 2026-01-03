# frozen_string_literal: true

require "test_helper"

module TraceBook
  class LlmSessionTest < ActiveSupport::TestCase
    setup do
      # Create interactions for User#42 across multiple sessions
      @interaction1 = Interaction.create!(
        provider: "openai",
        model: "gpt-4o",
        actor_type: "User",
        actor_id: 42,
        session_id: "session-a",
        total_tokens: 100,
        cost_total_cents: 10,
        latency_ms: 500,
        review_state: :pending,
        metadata: { "context_label" => "Chat about weather" }
      )

      @interaction2 = Interaction.create!(
        provider: "openai",
        model: "gpt-4o",
        actor_type: "User",
        actor_id: 42,
        session_id: "session-a",
        total_tokens: 200,
        cost_total_cents: 20,
        latency_ms: 600,
        review_state: :approved,
        metadata: { "context_label" => "Follow-up question" },
        created_at: 1.minute.from_now
      )

      @interaction3 = Interaction.create!(
        provider: "anthropic",
        model: "claude-3",
        actor_type: "User",
        actor_id: 42,
        session_id: "session-b",
        total_tokens: 150,
        cost_total_cents: 15,
        latency_ms: 400,
        review_state: :flagged
      )
    end

    # for_actor tests

    test "for_actor returns sessions for the specified actor" do
      sessions = LlmSession.for_actor("User", 42)

      assert_equal 2, sessions.size
      session_ids = sessions.map(&:session_id)
      assert_includes session_ids, "session-a"
      assert_includes session_ids, "session-b"
    end

    test "for_actor returns empty array for actor with no interactions" do
      sessions = LlmSession.for_actor("User", 999)

      assert_equal [], sessions
    end

    test "for_actor aggregates interactions_count correctly" do
      sessions = LlmSession.for_actor("User", 42)
      session_a = sessions.find { |s| s.session_id == "session-a" }
      session_b = sessions.find { |s| s.session_id == "session-b" }

      assert_equal 2, session_a.interactions_count
      assert_equal 1, session_b.interactions_count
    end

    test "for_actor aggregates total_tokens correctly" do
      sessions = LlmSession.for_actor("User", 42)
      session_a = sessions.find { |s| s.session_id == "session-a" }

      assert_equal 300, session_a.total_tokens # 100 + 200
    end

    test "for_actor aggregates total_cost_cents correctly" do
      sessions = LlmSession.for_actor("User", 42)
      session_a = sessions.find { |s| s.session_id == "session-a" }

      assert_equal 30, session_a.total_cost_cents # 10 + 20
    end

    test "for_actor calculates avg_latency_ms" do
      sessions = LlmSession.for_actor("User", 42)
      session_a = sessions.find { |s| s.session_id == "session-a" }

      assert_equal 550.0, session_a.avg_latency_ms # (500 + 600) / 2
    end

    test "for_actor counts review states correctly" do
      sessions = LlmSession.for_actor("User", 42)
      session_a = sessions.find { |s| s.session_id == "session-a" }
      session_b = sessions.find { |s| s.session_id == "session-b" }

      assert_equal 1, session_a.pending_count
      assert_equal 1, session_a.approved_count
      assert_equal 0, session_a.flagged_count

      assert_equal 0, session_b.pending_count
      assert_equal 0, session_b.approved_count
      assert_equal 1, session_b.flagged_count
    end

    test "for_actor orders by last_activity descending" do
      sessions = LlmSession.for_actor("User", 42)

      # session-a has the most recent interaction (1.minute.from_now)
      assert_equal "session-a", sessions.first.session_id
    end

    test "for_actor gets context_label from latest interaction" do
      sessions = LlmSession.for_actor("User", 42)
      session_a = sessions.find { |s| s.session_id == "session-a" }

      # Should get label from @interaction2 (created later)
      assert_equal "Follow-up question", session_a.context_label
    end

    # find tests

    test "find returns specific session" do
      session = LlmSession.find("User", 42, "session-a")

      assert_not_nil session
      assert_equal "session-a", session.session_id
      assert_equal "User", session.actor_type
      assert_equal 42, session.actor_id
    end

    test "find returns nil for non-existent session" do
      session = LlmSession.find("User", 42, "nonexistent")

      assert_nil session
    end

    # interactions method tests

    test "interactions returns all interactions for session" do
      session = LlmSession.find("User", 42, "session-a")
      interactions = session.interactions

      assert_equal 2, interactions.count
      assert interactions.all? { |i| i.session_id == "session-a" }
    end

    test "interactions are ordered by created_at ascending" do
      session = LlmSession.find("User", 42, "session-a")
      interactions = session.interactions

      assert interactions.first.created_at <= interactions.last.created_at
    end

    # review_summary tests

    test "review_summary returns :has_flagged when flagged_count positive" do
      session = LlmSession.find("User", 42, "session-b")

      assert_equal :has_flagged, session.review_summary
    end

    test "review_summary returns :has_pending when pending but no flagged" do
      session = LlmSession.find("User", 42, "session-a")

      assert_equal :has_pending, session.review_summary
    end

    test "review_summary returns :all_approved when no pending or flagged" do
      # Update all interactions in session-a to approved
      Interaction.where(session_id: "session-a").update_all(review_state: :approved)
      sessions = LlmSession.for_actor("User", 42)
      session_a = sessions.find { |s| s.session_id == "session-a" }

      assert_equal :all_approved, session_a.review_summary
    end

    # formatted helpers tests

    test "formatted_cost returns dollar amount" do
      session = LlmSession.find("User", 42, "session-a")

      assert_equal "$0.3", session.formatted_cost
    end

    test "formatted_latency returns seconds" do
      session = LlmSession.find("User", 42, "session-a")

      assert_equal "0.6s", session.formatted_latency
    end

    # Edge cases

    test "for_actor handles actor with single interaction" do
      Interaction.create!(
        provider: "openai",
        model: "gpt-4",
        actor_type: "Admin",
        actor_id: 1,
        session_id: "solo-session",
        total_tokens: 50
      )

      sessions = LlmSession.for_actor("Admin", 1)

      assert_equal 1, sessions.size
      assert_equal "solo-session", sessions.first.session_id
      assert_equal 1, sessions.first.interactions_count
    end

    test "for_actor handles nil metadata gracefully" do
      Interaction.create!(
        provider: "openai",
        model: "gpt-4",
        actor_type: "Guest",
        actor_id: 1,
        session_id: "no-metadata-session",
        total_tokens: 50,
        metadata: nil
      )

      sessions = LlmSession.for_actor("Guest", 1)

      assert_equal 1, sessions.size
      assert_nil sessions.first.context_label
    end
  end
end
