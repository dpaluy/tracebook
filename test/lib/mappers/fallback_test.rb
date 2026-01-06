require "test_helper"

module TraceBook
  module Mappers
    class FallbackTest < ActiveSupport::TestCase
      test "passes through meta fields when no provider-specific mapper exists" do
        normalized = Mappers.normalize(
          "custom-provider",
          raw_request: { "model" => "gpt-x", "prompt" => "Ping" },
          raw_response: { "content" => "Pong" },
          meta: {
            project: "demo",
            request_text: "Ping",
            response_text: "Pong",
            input_tokens: 10,
            output_tokens: 8,
            latency_ms: 250,
            status: :error,
            error_class: "TimeoutError",
            error_message: "Request timed out",
            tags: [ "custom" ],
            metadata: { "session_path" => "/foo/bar" },
            actor: "user-123",
            parent_id: 99,
            session_id: "sess-abc"
          }
        )

        assert_equal "custom-provider", normalized.provider
        assert_equal "gpt-x", normalized.model
        assert_equal "demo", normalized.project
        assert_equal "Ping", normalized.request_text
        assert_equal "Pong", normalized.response_text
        assert_equal 10, normalized.input_tokens
        assert_equal 8, normalized.output_tokens
        assert_equal 250, normalized.latency_ms
        assert_equal :error, normalized.status
        assert_equal "TimeoutError", normalized.error_class
        assert_equal "Request timed out", normalized.error_message
        assert_equal [ "custom" ], normalized.tags
        assert_equal({ "session_path" => "/foo/bar" }, normalized.metadata)
        assert_equal "user-123", normalized.actor
        assert_equal 99, normalized.parent_id
        assert_equal "sess-abc", normalized.session_id
      end
    end
  end
end
