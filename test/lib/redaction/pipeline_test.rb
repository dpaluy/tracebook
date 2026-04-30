# frozen_string_literal: true

require "test_helper"

module Tracebook
  module Redaction
    class PipelineTest < ActiveSupport::TestCase
      test "applies multiple patterns" do
        pipeline = Pipeline.new(patterns: [ PATTERNS[:email], PATTERNS[:phone] ])

        result = pipeline.call("Email user@test.com or call 555-123-4567")
        assert_equal "Email [EMAIL] or call [PHONE]", result
      end

      test "applies custom redactors after patterns" do
        custom = ->(text) { text.gsub(/MRN-\d{8}/, "[MEDICAL_RECORD]") }
        pipeline = Pipeline.new(
          patterns: [ PATTERNS[:email] ],
          custom_redactors: [ custom ]
        )

        result = pipeline.call("Patient MRN-12345678 email patient@hospital.com")
        assert_equal "Patient [MEDICAL_RECORD] email [EMAIL]", result
      end

      test "does not pass scope to generic one-argument custom redactors" do
        custom = ->(text) { text.gsub(/secret/i, "[SECRET]") }
        pipeline = Pipeline.new(custom_redactors: [ custom ])

        assert_equal "The [SECRET]", pipeline.call("The secret", scope: "chat-1")
      end

      test "passes scope to openai privacy filter redactor" do
        requests = []
        client = Object.new
        client.define_singleton_method(:detect) do |text|
          requests << text
          { "detected_spans" => [] }
        end
        redactor = OpenAiPrivacyFilter.new(client: client)
        pipeline = Pipeline.new(custom_redactors: [ redactor ])

        2.times { pipeline.call("Alice", scope: "chat-1") }

        assert_equal [ "Alice" ], requests
      end

      test "passes scope to custom redactors that accept the keyword" do
        received_scope = nil
        custom = ->(text, scope: nil) {
          received_scope = scope
          text
        }
        pipeline = Pipeline.new(custom_redactors: [ custom ])

        assert_equal "hello", pipeline.call("hello", scope: "chat-1")
        assert_equal "chat-1", received_scope
      end

      test "returns text unchanged when no patterns configured" do
        pipeline = Pipeline.new
        assert_equal "hello@world.com", pipeline.call("hello@world.com")
      end

      test "returns non-string values unchanged" do
        pipeline = Pipeline.new(patterns: [ PATTERNS[:email] ])
        assert_nil pipeline.call(nil)
      end

      test "active? reflects configuration" do
        empty = Pipeline.new
        assert_not empty.active?

        with_patterns = Pipeline.new(patterns: [ PATTERNS[:email] ])
        assert with_patterns.active?

        with_custom = Pipeline.new(custom_redactors: [ ->(t) { t } ])
        assert with_custom.active?
      end
    end
  end
end
