# frozen_string_literal: true

require "test_helper"

module Tracebook
  class CommentTest < ActiveSupport::TestCase
    setup do
      @review = ChatReview.create!(chat_type: "Chat", chat_id: 1)
    end

    test "validates presence of author" do
      comment = Comment.new(body: "Test comment", chat_review: @review)
      assert_not comment.valid?
      assert_includes comment.errors.attribute_names, :author
    end

    test "validates presence of body" do
      comment = Comment.new(author: "Test User", chat_review: @review)
      assert_not comment.valid?
      assert_includes comment.errors.attribute_names, :body
    end

    test "valid with all required attributes" do
      comment = Comment.new(author: "Test User", body: "Test comment", chat_review: @review)
      assert comment.valid?
    end

    test "belongs to chat_review" do
      comment = Comment.create!(author: "Test User", body: "Test", chat_review: @review)
      assert_equal @review, comment.chat_review
    end

    test "comments are destroyed when chat_review is destroyed" do
      Comment.create!(author: "Test User", body: "Test", chat_review: @review)

      assert_difference -> { Comment.count }, -1 do
        @review.destroy
      end
    end

    test "chronological scope orders by created_at ascending" do
      c1 = Comment.create!(author: "User", body: "First", chat_review: @review, created_at: 2.minutes.ago)
      c2 = Comment.create!(author: "User", body: "Second", chat_review: @review, created_at: 1.minute.ago)

      assert_equal [ c1.id, c2.id ], Comment.chronological.pluck(:id)
    end
  end
end
