require "test_helper"

class TraceBookConfigTest < ActiveSupport::TestCase
  setup { TraceBook.reset_configuration! }

  teardown { TraceBook.reset_configuration! }

  test "provides default configuration values" do
    config = TraceBook.config

    assert_equal true, config.persist_async
    assert_equal 64 * 1024, config.inline_payload_bytes
    assert_equal "USD", config.default_currency
    assert_equal [ :csv, :ndjson ], config.export_formats
    assert_equal false, config.auto_subscribe_ruby_llm
    assert_equal false, config.auto_subscribe_active_agent
    assert_kind_of Array, config.redactors
    assert_equal 0, config.redactors.length  # No default redactors until new Pattern system is built
    assert_equal [], config.custom_redactors
  end

  test "configure yields mutable config then freezes it" do
    TraceBook.configure do |config|
      config.project_name = "my_app"
      config.inline_payload_bytes = 32 * 1024
      config.custom_redactors = [ ->(payload) { payload } ]
    end

    config = TraceBook.config
    assert_equal "my_app", config.project_name
    assert_equal 32 * 1024, config.inline_payload_bytes
    assert config.frozen?
    assert config.redactors.frozen?
    assert config.custom_redactors.frozen?
  end

  test "reconfiguring after freeze raises configuration error" do
    TraceBook.configure { |_config| }

    assert_raises TraceBook::ConfigurationError do
      TraceBook.configure { |_config| }
    end
  end
end
