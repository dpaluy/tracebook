# frozen_string_literal: true

require "test_helper"

class ChatsFlowTest < ActionDispatch::IntegrationTest
  include TracebookTestHostApp

  setup do
    clear_tracebook_test_data!
    configure_tracebook_test_host!
  end

  teardown do
    TraceBook.reset_configuration!
  end

  test "show scopes the comment form body under comment params" do
    chat = TracebookTestChat.create!
    TracebookTestMessage.create!(chat: chat, role: "user", content: "Hello")

    get "/tracebook/chats/#{chat.id}"

    assert_response :success
    assert_select "textarea[name='comment[body]']"
  end

  test "create comment persists a review comment for the chat" do
    chat = TracebookTestChat.create!

    assert_difference -> { Tracebook::ChatReview.count }, 1 do
      assert_difference -> { Tracebook::Comment.count }, 1 do
        post "/tracebook/chats/#{chat.id}/comments", params: { comment: { body: "Needs follow-up" } }
      end
    end

    assert_redirected_to "/tracebook/chats/#{chat.id}"

    review = Tracebook::ChatReview.find_by!(chat_type: chat.class.name, chat_id: chat.id)
    assert_equal [ "Needs follow-up" ], review.comments.pluck(:body)
    assert_equal [ "Anonymous" ], review.comments.pluck(:author)
  end

  test "pending filter includes chats with no review record yet" do
    unreviewed_chat = TracebookTestChat.create!
    pending_chat = TracebookTestChat.create!
    approved_chat = TracebookTestChat.create!

    Tracebook::ChatReview.create!(chat: pending_chat)
    Tracebook::ChatReview.create!(
      chat: approved_chat,
      review_state: :approved,
      reviewed_at: Time.current,
      reviewed_by: "admin"
    )

    get "/tracebook/chats", params: { filters: { review_state: "pending" } }

    assert_response :success
    assert_select "a[href='/tracebook/chats/#{unreviewed_chat.id}']", text: "##{unreviewed_chat.id}"
    assert_select "a[href='/tracebook/chats/#{pending_chat.id}']", text: "##{pending_chat.id}"
    assert_select "a[href='/tracebook/chats/#{approved_chat.id}']", count: 0
  end
end
