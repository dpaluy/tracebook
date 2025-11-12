require "test_helper"

module TraceBook
  module Mappers
    class OllamaTest < ActiveSupport::TestCase
      test "normalizes basic response" do
        normalized = Mappers.normalize(
          "ollama",
          raw_request: { "model" => "llama3", "prompt" => "Say hi" },
          raw_response: { "response" => "Hi from Ollama", "total_duration" => 1.23, "eval_count" => 42 },
          meta: { project: "demo", latency_ms: 123 }
        )

        assert_equal "ollama", normalized.provider
        assert_equal "llama3", normalized.model
        assert_equal "Say hi", normalized.request_text
        assert_equal "Hi from Ollama", normalized.response_text
        assert_equal 123, normalized.latency_ms
        assert_equal({ "eval_count" => 42 }, normalized.metadata)
      end
    end
  end
end
