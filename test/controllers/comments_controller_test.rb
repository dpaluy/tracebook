# frozen_string_literal: true

require "test_helper"

module TraceBook
  class CommentsControllerTest < ActionDispatch::IntegrationTest
    include Tracebook::Engine.routes.url_helpers

    setup do
      @routes = Tracebook::Engine.routes
      @interaction = Interaction.create!(
        provider: "openai",
        model: "gpt-4o",
        status: :success,
        review_state: :pending,
        total_tokens: 100
      )
    end

    test "creates comment with valid body" do
      assert_difference -> { Comment.count }, 1 do
        post interaction_comments_path(@interaction), params: {
          comment: { body: "This looks good!" }
        }
      end

      assert_redirected_to interaction_path(@interaction)
      assert_equal "Comment added", flash[:notice]

      comment = Comment.last
      assert_equal "This looks good!", comment.body
      assert_equal @interaction.id, comment.interaction_id
    end

    test "sets author to Anonymous when no current_user" do
      post interaction_comments_path(@interaction), params: {
        comment: { body: "Test comment" }
      }

      comment = Comment.last
      assert_equal "Anonymous", comment.author
    end

    test "fails to create comment with blank body" do
      assert_no_difference -> { Comment.count } do
        post interaction_comments_path(@interaction), params: {
          comment: { body: "" }
        }
      end

      assert_redirected_to interaction_path(@interaction)
      assert_equal "Failed to add comment", flash[:alert]
    end

    test "fails to create comment with nil body" do
      assert_no_difference -> { Comment.count } do
        post interaction_comments_path(@interaction), params: {
          comment: { body: nil }
        }
      end

      assert_redirected_to interaction_path(@interaction)
      assert_equal "Failed to add comment", flash[:alert]
    end

    test "returns 404 for non-existent interaction" do
      post interaction_comments_path(999999), params: {
        comment: { body: "Test" }
      }
      assert_response :not_found
    end

    test "comment is associated with correct interaction" do
      interaction2 = Interaction.create!(
        provider: "anthropic",
        model: "claude-3",
        status: :success,
        total_tokens: 50
      )

      post interaction_comments_path(@interaction), params: {
        comment: { body: "Comment on first" }
      }

      post interaction_comments_path(interaction2), params: {
        comment: { body: "Comment on second" }
      }

      assert_equal 1, @interaction.comments.count
      assert_equal 1, interaction2.comments.count
      assert_equal "Comment on first", @interaction.comments.first.body
      assert_equal "Comment on second", interaction2.comments.first.body
    end
  end
end
