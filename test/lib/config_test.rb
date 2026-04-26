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
    assert_not config.openai_privacy_filter.enabled?
    assert_equal Tracebook::Redaction::OpenAiPrivacyFilter::DEFAULT_ENDPOINT,
      config.openai_privacy_filter.endpoint
    assert_equal Tracebook::Redaction::OpenAiPrivacyFilter::DEFAULT_TIMEOUT,
      config.openai_privacy_filter.timeout
    assert_equal :fallback, config.openai_privacy_filter.failure_mode
    assert_equal "[PERSON]", config.openai_privacy_filter.label_map.fetch("private_person")
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
    assert config.openai_privacy_filter.frozen?
    assert config.openai_privacy_filter.label_map.frozen?
  end

  test "reconfiguring after freeze raises configuration error" do
    TraceBook.configure { |_config| }

    assert_raises TraceBook::ConfigurationError do
      TraceBook.configure { |_config| }
    end
  end

  test "enabled openai privacy filter rejects non-loopback endpoint" do
    assert_raises TraceBook::ConfigurationError do
      TraceBook.configure do |config|
        config.openai_privacy_filter.enabled = true
        config.openai_privacy_filter.endpoint = "https://example.com/redact"
      end
    end
  end
end
