require "test_helper"

class TraceBookConfigTest < ActiveSupport::TestCase
  setup { TraceBook.reset_configuration! }

  teardown { TraceBook.reset_configuration! }

  test "provides default configuration values" do
    config = TraceBook.config

    assert_equal "Chat", config.chat_class
    assert_equal "Message", config.message_class
    assert_equal "USD", config.default_currency
    assert_equal 25, config.per_page
    assert_nil config.actor_display
  end

  test "configure yields mutable config then freezes it" do
    TraceBook.configure do |config|
      config.chat_class = "Conversation"
      config.message_class = "ChatMessage"
      config.per_page = 50
    end

    config = TraceBook.config
    assert_equal "Conversation", config.chat_class
    assert_equal "ChatMessage", config.message_class
    assert_equal 50, config.per_page
    assert config.frozen?
  end

  test "reconfiguring after freeze raises configuration error" do
    TraceBook.configure { |_config| }

    assert_raises TraceBook::ConfigurationError do
      TraceBook.configure { |_config| }
    end
  end
end
