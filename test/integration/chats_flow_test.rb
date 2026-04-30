# frozen_string_literal: true

require "test_helper"

class ChatsFlowTest < ActionDispatch::IntegrationTest
  include TracebookTestHostApp

  class PrivacyFilterSequenceClient
    attr_reader :texts

    def initialize(*responses)
      @responses = responses
      @texts = []
    end

    def detect(text)
      texts << text
      @responses.shift || { "detected_spans" => [] }
    end
  end

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

  test "show redacts message content in html and json export" do
    address = "12822 Majestic Oaks Dr"
    configure_tracebook_test_host_with_redaction!(address)
    chat = TracebookTestChat.create!
    TracebookTestMessage.create!(chat: chat, role: "user", content: "I live at #{address}")

    get "/tracebook/chats/#{chat.id}"

    assert_response :success
    assert_includes response.body, "I live at [ADDRESS]"
    assert_not_includes response.body, address

    get "/tracebook/chats/#{chat.id}.json"

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "I live at [ADDRESS]", payload.fetch("messages").first.fetch("content")
    assert_not_includes response.body, address
  end

  test "show uses openai privacy filter scope across html and json export" do
    address = "12822 Majestic Oaks Dr"
    user_message = "I live at #{address}"
    assistant_message = "Nearest hospital to #{address}"
    user_start = user_message.index(address)
    client = PrivacyFilterSequenceClient.new(
      {
        "detected_spans" => [
          { "start" => user_start, "end" => user_start + address.length, "label" => "private_address" }
        ]
      },
      { "detected_spans" => [] }
    )
    configure_tracebook_test_host_with_openai_client!(client)
    chat = TracebookTestChat.create!
    timestamp = Time.current
    TracebookTestMessage.create!(chat: chat, role: "user", content: user_message, created_at: timestamp, updated_at: timestamp)
    TracebookTestMessage.create!(chat: chat, role: "assistant", content: assistant_message, created_at: timestamp + 1.second, updated_at: timestamp + 1.second)

    get "/tracebook/chats/#{chat.id}"

    assert_response :success
    assert_includes response.body, "I live at [ADDRESS]"
    assert_includes response.body, "Nearest hospital to [ADDRESS]"
    assert_not_includes response.body, address
    assert_equal [ user_message, "Nearest hospital to [ADDRESS]" ], client.texts

    get "/tracebook/chats/#{chat.id}.json"

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal [ "I live at [ADDRESS]", "Nearest hospital to [ADDRESS]" ],
      payload.fetch("messages").map { |message| message.fetch("content") }
    assert_not_includes response.body, address
    assert_equal [ user_message, "Nearest hospital to [ADDRESS]" ], client.texts
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

  private

  def configure_tracebook_test_host_with_redaction!(address)
    TraceBook.reset_configuration!
    TraceBook.configure do |config|
      config.chat_class = "TracebookTestChat"
      config.message_class = "TracebookTestMessage"
      config.redact_pattern(/#{Regexp.escape(address)}/, "[ADDRESS]", name: "address")
    end
  end

  def configure_tracebook_test_host_with_openai_client!(client)
    TraceBook.reset_configuration!
    TraceBook.configure do |config|
      config.chat_class = "TracebookTestChat"
      config.message_class = "TracebookTestMessage"
      config.openai_privacy_filter.enabled = true
    end

    openai_redactor = Tracebook.config.redaction_pipeline.custom_redactors.grep(Tracebook::Redaction::OpenAiPrivacyFilter).first
    openai_redactor.instance_variable_set(:@client, client)
  end
end
