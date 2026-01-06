# frozen_string_literal: true

require "test_helper"

module TraceBook
  class ActorsControllerTest < ActionDispatch::IntegrationTest
    include Tracebook::Engine.routes.url_helpers

    setup do
      @routes = Tracebook::Engine.routes
      @interaction = Interaction.create!(
        provider: "openai",
        model: "gpt-4o",
        status: :success,
        review_state: :pending,
        actor_type: "User",
        actor_id: 42,
        session_id: "test-session-1",
        total_tokens: 100,
        cost_total_cents: 5
      )
    end

    # Index tests

    test "renders actors index" do
      get actors_path
      assert_response :success
      assert_match "User", @response.body
    end

    test "index aggregates actors with stats" do
      Interaction.create!(
        provider: "anthropic",
        model: "claude-3",
        actor_type: "User",
        actor_id: 42,
        session_id: "test-session-2",
        total_tokens: 50,
        cost_total_cents: 3
      )

      get actors_path
      assert_response :success
    end

    # Show tests

    test "renders actor show page with valid type" do
      get actor_path(type: "users", id: 42)
      assert_response :success
    end

    test "returns 404 for invalid actor type format" do
      get actor_path(type: "invalid__type", id: 42)
      assert_response :not_found
    end

    test "returns 404 for actor type not in database" do
      get actor_path(type: "admins", id: 1)
      assert_response :not_found
    end

    test "returns 404 for type with invalid characters" do
      # URL encoding happens automatically, but the regex should reject non-alphanumeric
      get actor_path(type: "users!", id: 42)
      assert_response :not_found
    end

    # Session tests

    test "renders llm_session page for valid session" do
      get actor_session_path(type: "users", id: 42, session_id: "test-session-1")
      assert_response :success
      # Page should show the actor name and model
      assert_match "User #42", @response.body
      assert_match "gpt-4o", @response.body
    end

    # Type parameter validation tests

    test "type_from_param validates against database actor types" do
      # Create interaction with different actor type
      Interaction.create!(
        provider: "openai",
        model: "gpt-4",
        actor_type: "VendorUser",
        actor_id: 1,
        total_tokens: 10,
        cost_total_cents: 1
      )

      # Should work for VendorUser now
      get actor_path(type: "vendor_users", id: 1)
      assert_response :success
    end

    test "type_from_param rejects types not in database" do
      # AdminUser doesn't exist in database
      get actor_path(type: "admin_users", id: 1)
      assert_response :not_found
    end
  end
end
