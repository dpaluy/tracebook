require "test_helper"

module TraceBook
  module Mappers
    class OpenAITest < ActiveSupport::TestCase
      test "normalizes chat completion payload" do
        normalized = Mappers.normalize(
          "openai",
          raw_request: {
            "model" => "gpt-4o",
            "messages" => [
              { "role" => "system", "content" => "You are helpful." },
              { "role" => "user", "content" => "Hello there" }
            ]
          },
          raw_response: {
            "choices" => [
              {
                "message" => { "role" => "assistant", "content" => "Hi!" },
                "finish_reason" => "stop"
              }
            ],
            "usage" => { "prompt_tokens" => 12, "completion_tokens" => 7 }
          },
          meta: { project: "demo", tags: [ "chat" ], status: :success }
        )

        assert_equal "openai", normalized.provider
        assert_equal "gpt-4o", normalized.model
        assert_equal "demo", normalized.project
        assert_equal "You are helpful.\n\nHello there", normalized.request_text
        assert_equal "Hi!", normalized.response_text
        assert_equal 12, normalized.input_tokens
        assert_equal 7, normalized.output_tokens
        assert_equal :success, normalized.status
        assert_equal [ "chat" ], normalized.tags
        assert_equal({ "finish_reason" => "stop" }, normalized.metadata)
      end
    end
  end
end
