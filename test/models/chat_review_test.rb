require "test_helper"

module Tracebook
  class ChatReviewTest < ActiveSupport::TestCase
    test "validates presence of chat_type and chat_id" do
      review = ChatReview.new
      assert_not review.valid?
      assert_includes review.errors[:chat_type], "can't be blank"
      assert_includes review.errors[:chat_id], "can't be blank"
    end

    test "defaults to pending review state" do
      review = ChatReview.create!(chat_type: "Chat", chat_id: 1)
      assert_equal "pending", review.review_state
    end

    test "can be approved" do
      review = ChatReview.create!(chat_type: "Chat", chat_id: 1)
      review.update!(review_state: :approved, reviewed_at: Time.current, reviewed_by: "admin")
      assert review.review_state_approved?
    end

    test "can be flagged" do
      review = ChatReview.create!(chat_type: "Chat", chat_id: 1)
      review.update!(review_state: :flagged, review_comment: "Needs attention")
      assert review.review_state_flagged?
      assert_equal "Needs attention", review.review_comment
    end

    test "has many comments" do
      review = ChatReview.create!(chat_type: "Chat", chat_id: 1)
      review.comments.create!(author: "tester", body: "Looks good")
      assert_equal 1, review.comments.count
    end
  end
end
