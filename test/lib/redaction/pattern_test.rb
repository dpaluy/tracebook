# frozen_string_literal: true

require "test_helper"

module Tracebook
  module Redaction
    class PatternTest < ActiveSupport::TestCase
      test "email pattern redacts email addresses" do
        pattern = PATTERNS[:email]
        assert_equal "Contact [EMAIL] for info", pattern.redact("Contact user@example.com for info")
      end

      test "phone pattern redacts phone numbers" do
        pattern = PATTERNS[:phone]
        assert_equal "Call [PHONE]", pattern.redact("Call (555) 123-4567")
        assert_equal "Call [PHONE]", pattern.redact("Call 555-123-4567")
        assert_equal "Call [PHONE]", pattern.redact("Call 555.123.4567")
      end

      test "ssn pattern redacts valid SSNs" do
        pattern = PATTERNS[:ssn]
        assert_equal "SSN: [SSN]", pattern.redact("SSN: 123-45-6789")
      end

      test "ssn pattern skips invalid area numbers" do
        pattern = PATTERNS[:ssn]
        assert_equal "SSN: 000-45-6789", pattern.redact("SSN: 000-45-6789")
        assert_equal "SSN: 666-45-6789", pattern.redact("SSN: 666-45-6789")
        assert_equal "SSN: 900-45-6789", pattern.redact("SSN: 900-45-6789")
      end

      test "credit_card pattern redacts valid card numbers" do
        pattern = PATTERNS[:credit_card]
        assert_equal "Card: [CREDIT_CARD]", pattern.redact("Card: 4111 1111 1111 1111")
      end

      test "credit_card pattern skips numbers failing Luhn" do
        pattern = PATTERNS[:credit_card]
        assert_equal "Card: 4111 1111 1111 1112", pattern.redact("Card: 4111 1111 1111 1112")
      end

      test "openai_key pattern redacts API keys" do
        pattern = PATTERNS[:openai_key]
        assert_equal "Key: [KEY]", pattern.redact("Key: sk-abc123def456ghi789jkl012mno")
      end

      test "anthropic_key pattern redacts API keys" do
        pattern = PATTERNS[:anthropic_key]
        assert_equal "Key: [KEY]", pattern.redact("Key: sk-ant-abc123def456ghi789jkl012mno")
      end

      test "bearer_token pattern redacts tokens" do
        pattern = PATTERNS[:bearer_token]
        assert_equal "Auth: Bearer [REDACTED]", pattern.redact("Auth: Bearer eyJhbGciOiJIUzI1NiJ9")
      end

      test "ipv4 pattern redacts valid IP addresses" do
        pattern = PATTERNS[:ipv4]
        assert_equal "Server at [IP_ADDRESS]", pattern.redact("Server at 192.168.1.100")
      end

      test "ipv4 pattern skips invalid octets" do
        pattern = PATTERNS[:ipv4]
        assert_equal "Version 999.999.999.999", pattern.redact("Version 999.999.999.999")
      end

      test "phone pattern does not match inside longer digit strings" do
        pattern = PATTERNS[:phone]
        assert_equal "account 123456789012345", pattern.redact("account 123456789012345")
      end

      test "returns non-string values unchanged" do
        pattern = PATTERNS[:email]
        assert_nil pattern.redact(nil)
        assert_equal 42, pattern.redact(42)
      end

      test "custom pattern with validator" do
        pattern = Pattern.new(
          name: :test,
          regex: /\d{4}/,
          replacement: "[REDACTED]",
          validator: ->(match) { match.to_i > 1000 }
        )
        assert_equal "Code: [REDACTED]", pattern.redact("Code: 2024")
        assert_equal "Code: 0001", pattern.redact("Code: 0001")
      end
    end
  end
end
