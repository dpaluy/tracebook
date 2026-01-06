# frozen_string_literal: true

require "test_helper"

module TraceBook
  class CommentTest < ActiveSupport::TestCase
    setup do
      @interaction = Interaction.create!(
        provider: "openai",
        model: "gpt-4o",
        status: :success,
        total_tokens: 100
      )
    end

    # Validation tests

    test "validates presence of author" do
      comment = Comment.new(body: "Test comment", interaction: @interaction)

      assert_not comment.valid?
      assert_includes comment.errors.attribute_names, :author
    end

    test "validates presence of body" do
      comment = Comment.new(author: "Test User", interaction: @interaction)

      assert_not comment.valid?
      assert_includes comment.errors.attribute_names, :body
    end

    test "valid with all required attributes" do
      comment = Comment.new(
        author: "Test User",
        body: "This is a test comment",
        interaction: @interaction
      )

      assert comment.valid?
    end

    # Association tests

    test "belongs to interaction" do
      comment = Comment.create!(
        author: "Test User",
        body: "Test comment",
        interaction: @interaction
      )

      assert_equal @interaction, comment.interaction
    end

    test "interaction can have many comments" do
      Comment.create!(author: "User 1", body: "First comment", interaction: @interaction)
      Comment.create!(author: "User 2", body: "Second comment", interaction: @interaction)

      assert_equal 2, @interaction.comments.count
    end

    test "comments are destroyed when interaction is destroyed" do
      Comment.create!(author: "Test User", body: "Test comment", interaction: @interaction)

      assert_difference -> { Comment.count }, -1 do
        @interaction.destroy
      end
    end

    # Scope tests

    test "chronological scope orders by created_at ascending" do
      comment1 = Comment.create!(
        author: "User",
        body: "First",
        interaction: @interaction,
        created_at: 2.minutes.ago
      )
      comment2 = Comment.create!(
        author: "User",
        body: "Second",
        interaction: @interaction,
        created_at: 1.minute.ago
      )
      comment3 = Comment.create!(
        author: "User",
        body: "Third",
        interaction: @interaction,
        created_at: Time.current
      )

      ordered = Comment.chronological

      assert_equal [comment1.id, comment2.id, comment3.id], ordered.pluck(:id)
    end

    test "interaction.comments returns in chronological order" do
      comment1 = Comment.create!(
        author: "User",
        body: "First",
        interaction: @interaction,
        created_at: 2.minutes.ago
      )
      comment2 = Comment.create!(
        author: "User",
        body: "Second",
        interaction: @interaction,
        created_at: 1.minute.ago
      )

      comments = @interaction.comments

      assert_equal comment1.id, comments.first.id
      assert_equal comment2.id, comments.last.id
    end

    # Edge cases

    test "allows long comment bodies" do
      long_body = "A" * 10_000
      comment = Comment.new(
        author: "Test User",
        body: long_body,
        interaction: @interaction
      )

      assert comment.valid?
    end

    test "author can contain special characters" do
      comment = Comment.new(
        author: "User <test@example.com>",
        body: "Test",
        interaction: @interaction
      )

      assert comment.valid?
    end
  end
end
