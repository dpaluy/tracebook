require "test_helper"

module TraceBook
  class InteractionsControllerTest < ActionDispatch::IntegrationTest
    include Tracebook::Engine.routes.url_helpers

    setup do
      @routes = Tracebook::Engine.routes
      Interaction.create!(
        provider: "openai",
        model: "gpt-4o",
        status: :success,
        review_state: :pending,
        total_tokens: 10
      )
    end

    test "renders index" do
      get interactions_path
      assert_response :success
      assert_match "TraceBook Interactions", @response.body
    end

    test "renders show" do
      interaction = Interaction.first
      get interaction_path(interaction)
      assert_response :success
      assert_match interaction.provider, @response.body
    end

    test "rejects invalid review state" do
      interaction = Interaction.first

      post review_interaction_path(interaction), params: { review_state: "invalid" }

      assert_redirected_to interaction_path(interaction)
      assert_equal "Invalid review state: invalid", flash[:alert]
      assert_equal "pending", interaction.reload.review_state
    end

    test "rejects invalid state in bulk review" do
      interaction = Interaction.first

      post bulk_review_interactions_path, params: { review_state: "bad", interaction_ids: [ interaction.id ] }

      assert_redirected_to interactions_path
      assert_equal "Invalid review state: bad", flash[:alert]
      assert_equal "pending", interaction.reload.review_state
    end

    test "handles tag filter safely" do
      get interactions_path, params: { filters: { tag: "%foo" } }

      assert_response :success
    end
  end
end
