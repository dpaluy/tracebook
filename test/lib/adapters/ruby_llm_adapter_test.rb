require "test_helper"

module TraceBook
  module Adapters
    class RubyLLMAdapterTest < ActiveSupport::TestCase
      setup do
        Interaction.delete_all
        TraceBook.reset_configuration!
        TraceBook.configure do |config|
          config.persist_async = false
        end
      end

      teardown do
        TraceBook.reset_configuration!
        Interaction.delete_all
      end

      test "subscribes to notifications and records interaction" do
        RubyLLM.enable!

        ActiveSupport::Notifications.instrument("ruby_llm.request", {
          provider: "openai",
          request: { "model" => "gpt-4o", "messages" => [ { "content" => "Hi" } ] },
          response: { "choices" => [ { "message" => { "content" => "Hello" } } ], "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5 } },
          meta: { project: "demo" }
        })

        assert_equal 1, Interaction.count
        interaction = Interaction.first
        assert_equal "openai", interaction.provider
        assert_equal 15, interaction.total_tokens
      end

      test "captures token counts from Gemini response with usageMetadata" do
        RubyLLM.enable!

        ActiveSupport::Notifications.instrument("ruby_llm.request", {
          provider: "gemini",
          request: { "model" => "gemini-2.0-flash", "messages" => [ { "content" => "Hi" } ] },
          response: { 
            "content" => "Hello", 
            "usageMetadata" => { "promptTokenCount" => 50, "candidatesTokenCount" => 25 }
          },
          meta: { project: "demo" }
        })

        assert_equal 1, Interaction.count
        interaction = Interaction.first
        assert_equal "gemini", interaction.provider
        assert_equal 50, interaction.input_tokens
        assert_equal 25, interaction.output_tokens
        assert_equal 75, interaction.total_tokens
      end

      test "uses meta tokens over response tokens for Gemini" do
        RubyLLM.enable!

        ActiveSupport::Notifications.instrument("ruby_llm.request", {
          provider: "gemini",
          request: { "model" => "gemini-2.0-flash", "messages" => [ { "content" => "Hi" } ] },
          response: { 
            "content" => "Hello", 
            "usageMetadata" => { "promptTokenCount" => 50, "candidatesTokenCount" => 25 }
          },
          meta: { project: "demo", input_tokens: 100, output_tokens: 40 }
        })

        interaction = Interaction.last
        assert_equal 100, interaction.input_tokens, "Should prioritize meta tokens"
        assert_equal 40, interaction.output_tokens
      end
    end
  end
end
