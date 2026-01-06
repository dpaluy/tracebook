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
      assert_match "TraceBook", @response.body
    end

    test "index displays review column" do
      get interactions_path

      assert_response :success
      assert_select "th", text: "Review"
      assert_select ".tb-status", text: "pending"
    end

    test "renders show" do
      interaction = Interaction.first
      get interaction_path(interaction)
      assert_response :success
      assert_match(/#{interaction.provider}/i, @response.body)
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

    test "bulk review approves selected interactions" do
      interaction1 = Interaction.first
      interaction2 = Interaction.create!(provider: "anthropic", model: "claude-3", status: :success, total_tokens: 20)

      post bulk_review_interactions_path, params: { review_state: "approved", interaction_ids: [ interaction1.id, interaction2.id ] }

      assert_redirected_to interactions_path
      assert_equal "Updated 2 interactions", flash[:notice]
      assert_equal "approved", interaction1.reload.review_state
      assert_equal "approved", interaction2.reload.review_state
    end

    test "handles tag filter safely" do
      get interactions_path, params: { filters: { tag: "%foo" } }

      assert_response :success
    end

    test "renders pagination controls in turbo frame" do
      get interactions_path

      assert_response :success
      assert_select "turbo-frame#interactions_table" do
        assert_select "nav.tb-pagination"
      end
    end

    test "pagination links include turbo frame target" do
      # Create enough interactions to trigger pagination
      110.times do |i|
        Interaction.create!(provider: "openai", model: "gpt-4o-#{i}", status: :success, total_tokens: 10)
      end

      get interactions_path

      assert_response :success
      assert_match 'data-turbo-frame="interactions_table"', @response.body
    end

    test "pagination preserves filters across pages" do
      110.times do |i|
        Interaction.create!(provider: "anthropic", model: "claude-#{i}", status: :success, total_tokens: 10)
      end

      get interactions_path, params: { filters: { provider: "anthropic" }, page: 2 }

      assert_response :success
      assert_select "select[name='filters[provider]'] option[selected]", text: "anthropic"
    end
  end
end
