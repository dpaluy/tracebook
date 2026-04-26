# frozen_string_literal: true

require "test_helper"

class RedactionConfigTest < ActiveSupport::TestCase
  setup { Tracebook.reset_configuration! }
  teardown { Tracebook.reset_configuration! }

  test "redact enables individual patterns" do
    Tracebook.configure do |config|
      config.redact :email, :phone
    end

    pipeline = Tracebook.config.redaction_pipeline
    assert pipeline.active?
    assert_equal 2, pipeline.patterns.size
    assert_equal "Contact [EMAIL] at [PHONE]",
      pipeline.call("Contact user@test.com at 555-123-4567")
  end

  test "redact enables pattern groups" do
    Tracebook.configure do |config|
      config.redact :pii
    end

    pipeline = Tracebook.config.redaction_pipeline
    assert_equal 3, pipeline.patterns.size # email, phone, ssn
  end

  test "redact_pattern adds custom regex" do
    Tracebook.configure do |config|
      config.redact_pattern(/policy[:\s]*\d{10}/i, "[POLICY]", name: "policy")
    end

    pipeline = Tracebook.config.redaction_pipeline
    assert_equal "See [POLICY]", pipeline.call("See policy: 1234567890")
  end

  test "custom_redactors are applied" do
    Tracebook.configure do |config|
      config.custom_redactors << ->(text) { text.gsub(/secret/i, "[SECRET]") }
    end

    pipeline = Tracebook.config.redaction_pipeline
    assert_equal "The [SECRET] is safe", pipeline.call("The secret is safe")
  end

  test "openai privacy filter is disabled by default" do
    Tracebook.configure do |config|
      config.redact :email
    end

    pipeline = Tracebook.config.redaction_pipeline
    assert_empty pipeline.custom_redactors
  end

  test "openai privacy filter is appended when enabled" do
    Tracebook.configure do |config|
      config.custom_redactors << ->(text) { text.gsub(/secret/i, "[SECRET]") }
      config.openai_privacy_filter.enabled = true
    end

    redactors = Tracebook.config.redaction_pipeline.custom_redactors
    assert_equal 2, redactors.size
    assert_instance_of Proc, redactors.first
    assert_instance_of Tracebook::Redaction::OpenAiPrivacyFilter, redactors.second
  end

  test "Tracebook.redact uses configured pipeline" do
    Tracebook.configure do |config|
      config.redact :email
    end

    assert_equal "Send to [EMAIL]", Tracebook.redact("Send to user@test.com")
  end

  test "redact_pattern assigns unique names to unnamed patterns" do
    Tracebook.configure do |config|
      config.redact_pattern(/foo/, "[FOO]")
      config.redact_pattern(/bar/, "[BAR]")
    end

    pipeline = Tracebook.config.redaction_pipeline
    names = pipeline.patterns.map(&:name)
    assert_equal names.uniq, names
  end

  test "raises on unknown pattern name" do
    assert_raises(ArgumentError) do
      Tracebook.configure do |config|
        config.redact :nonexistent
      end
    end
  end

  test "no redaction by default" do
    Tracebook.configure { |_| }

    pipeline = Tracebook.config.redaction_pipeline
    assert_not pipeline.active?
    assert_equal "user@test.com", Tracebook.redact("user@test.com")
  end
end
