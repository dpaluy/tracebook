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
    assert_equal [], config.enabled_patterns
    assert_equal [], config.custom_patterns
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

  # Config DSL tests (T7)

  test "redact enables individual patterns" do
    TraceBook.configure do |config|
      config.redact :email, :phone
    end

    config = TraceBook.config
    assert_equal [ :email, :phone ], config.enabled_patterns
    assert_equal 2, config.active_patterns.size
    assert config.active_patterns.all? { |p| p.is_a?(Tracebook::Redactors::Pattern) }
  end

  test "redact raises ConfigurationError for unknown pattern" do
    assert_raises TraceBook::ConfigurationError do
      TraceBook.configure do |config|
        config.redact :bogus_pattern
      end
    end
  end

  test "redact deduplicates patterns" do
    TraceBook.configure do |config|
      config.redact :email, :phone
      config.redact :email  # duplicate
    end

    config = TraceBook.config
    assert_equal [ :email, :phone ], config.enabled_patterns
  end

  test "redact_group enables all patterns in group" do
    TraceBook.configure do |config|
      config.redact_group :api_keys
    end

    config = TraceBook.config
    expected = [ :openai_key, :anthropic_key, :aws_key, :stripe_key, :github_token, :github_pat ]
    assert_equal expected, config.enabled_patterns
  end

  test "redact_group raises ConfigurationError for unknown group" do
    assert_raises TraceBook::ConfigurationError do
      TraceBook.configure do |config|
        config.redact_group :nonexistent_group
      end
    end
  end

  test "redact_group deduplicates with individual redact" do
    TraceBook.configure do |config|
      config.redact :openai_key
      config.redact_group :api_keys  # includes openai_key
    end

    config = TraceBook.config
    # openai_key should only appear once
    assert_equal 1, config.enabled_patterns.count(:openai_key)
  end

  test "redact_pattern adds custom pattern" do
    TraceBook.configure do |config|
      config.redact_pattern(/secret=\w+/, "[SECRET]")
    end

    config = TraceBook.config
    assert_equal 1, config.custom_patterns.size
    pattern = config.custom_patterns.first
    assert_equal(/secret=\w+/, pattern.regex)
    assert_equal "[SECRET]", pattern.replacement
    assert_equal "custom_1", pattern.name
  end

  test "redact_pattern accepts custom name" do
    TraceBook.configure do |config|
      config.redact_pattern(/mykey_\w+/, "[MYKEY]", name: "my_app_key")
    end

    config = TraceBook.config
    pattern = config.custom_patterns.first
    assert_equal "my_app_key", pattern.name
  end

  test "redact_pattern numbers multiple custom patterns" do
    TraceBook.configure do |config|
      config.redact_pattern(/first/, "[FIRST]")
      config.redact_pattern(/second/, "[SECOND]")
    end

    config = TraceBook.config
    assert_equal 2, config.custom_patterns.size
    assert_equal "custom_1", config.custom_patterns[0].name
    assert_equal "custom_2", config.custom_patterns[1].name
  end

  test "active_patterns combines enabled patterns and custom patterns" do
    TraceBook.configure do |config|
      config.redact :email
      config.redact_pattern(/custom/, "[CUSTOM]")
    end

    config = TraceBook.config
    active = config.active_patterns
    assert_equal 2, active.size
    assert_equal "email", active[0].name
    assert_equal "custom_1", active[1].name
  end

  test "enabled_patterns and custom_patterns are frozen after configure" do
    TraceBook.configure do |config|
      config.redact :email
      config.redact_pattern(/x/, "[X]")
    end

    config = TraceBook.config
    assert config.enabled_patterns.frozen?
    assert config.custom_patterns.frozen?
  end
end
