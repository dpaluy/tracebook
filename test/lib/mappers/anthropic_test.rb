require "test_helper"

module TraceBook
  module Mappers
    class AnthropicTest < ActiveSupport::TestCase
      test "normalizes messages with content blocks" do
        normalized = Mappers.normalize(
          "anthropic",
          raw_request: {
            "model" => "claude-3-sonnet",
            "messages" => [
              { "role" => "user", "content" => [ { "type" => "text", "text" => "Explain" } ] }
            ]
          },
          raw_response: {
            "content" => [
              { "type" => "text", "text" => "Here is an explanation." }
            ],
            "usage" => { "input_tokens" => 20, "output_tokens" => 15 }
          },
          meta: { project: "demo" }
        )

        assert_equal "anthropic", normalized.provider
        assert_equal "claude-3-sonnet", normalized.model
        assert_equal "Explain", normalized.request_text
        assert_equal "Here is an explanation.", normalized.response_text
        assert_equal 20, normalized.input_tokens
        assert_equal 15, normalized.output_tokens
        assert_equal({}, normalized.metadata)
      end
    end
  end
end
