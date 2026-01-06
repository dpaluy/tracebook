# frozen_string_literal: true

require "test_helper"

module TraceBook
  class InteractionsControllerTest < ActionDispatch::IntegrationTest
    include Tracebook::Engine.routes.url_helpers

    fixtures "tracebook/interactions"

    setup do
      @routes = Tracebook::Engine.routes
      @interaction = tracebook_interactions(:openai_gpt4o)
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
      get interaction_path(@interaction)
      assert_response :success
      assert_match(/#{@interaction.provider}/i, @response.body)
    end

    test "rejects invalid review state" do
      post review_interaction_path(@interaction), params: { review_state: "invalid" }

      assert_redirected_to interaction_path(@interaction)
      assert_equal "Invalid review state: invalid", flash[:alert]
      assert_equal "pending", @interaction.reload.review_state
    end

    test "rejects invalid state in bulk review" do
      post bulk_review_interactions_path, params: { review_state: "bad", interaction_ids: [ @interaction.id ] }

      assert_redirected_to interactions_path
      assert_equal "Invalid review state: bad", flash[:alert]
      assert_equal "pending", @interaction.reload.review_state
    end

    test "bulk review approves selected interactions" do
      interaction2 = tracebook_interactions(:anthropic_claude)

      post bulk_review_interactions_path, params: { review_state: "approved", interaction_ids: [ @interaction.id, interaction2.id ] }

      assert_redirected_to interactions_path
      assert_equal "Updated 2 interactions", flash[:notice]
      assert_equal "approved", @interaction.reload.review_state
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

    test "csv format returns csv content" do
      get interactions_path(format: :csv)

      assert_response :success
      assert_equal "text/csv", response.content_type
      assert_match(/tracebook-export-.*\.csv/, response.headers["Content-Disposition"])
    end

    test "csv format includes interaction data" do
      get interactions_path(format: :csv)

      assert_response :success
      assert_match "timestamp", response.body
      assert_match "provider", response.body
      assert_match "openai", response.body
    end

    test "csv format respects filters" do
      get interactions_path(format: :csv, filters: { provider: "openai" })

      assert_response :success
      assert_match "openai", response.body
      assert_no_match(/anthropic/, response.body)
    end
  end
end
