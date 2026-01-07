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
          provider: "gemini",
          request: { "model" => "gemini-2.0-flash", "messages" => [ { "content" => "Hi" } ] },
          response: {
            "role" => "assistant",
            "content" => "Hello!",
            "model_id" => "gemini-2.0-flash",
            "input_tokens" => 50,
            "output_tokens" => 25
          },
          meta: { project: "demo" }
        })

        assert_equal 1, Interaction.count
        interaction = Interaction.first
        assert_equal "gemini", interaction.provider
        assert_equal "gemini-2.0-flash", interaction.model
        assert_equal 50, interaction.input_tokens
        assert_equal 25, interaction.output_tokens
        assert_equal 75, interaction.total_tokens
      end

      test "captures token counts for OpenAI provider" do
        RubyLLM.enable!

        ActiveSupport::Notifications.instrument("ruby_llm.request", {
          provider: "openai",
          request: { "model" => "gpt-4o", "messages" => [ { "content" => "Hi" } ] },
          response: {
            "role" => "assistant",
            "content" => "Hello!",
            "model_id" => "gpt-4o",
            "input_tokens" => 100,
            "output_tokens" => 50
          },
          meta: { project: "demo" }
        })

        interaction = Interaction.last
        assert_equal "openai", interaction.provider
        assert_equal "gpt-4o", interaction.model
        assert_equal 100, interaction.input_tokens
        assert_equal 50, interaction.output_tokens
      end

      test "captures token counts for Anthropic provider" do
        RubyLLM.enable!

        ActiveSupport::Notifications.instrument("ruby_llm.request", {
          provider: "anthropic",
          request: { "model" => "claude-3-5-sonnet", "messages" => [ { "content" => "Hi" } ] },
          response: {
            "role" => "assistant",
            "content" => "Hello!",
            "model_id" => "claude-3-5-sonnet",
            "input_tokens" => 75,
            "output_tokens" => 30
          },
          meta: { project: "demo" }
        })

        interaction = Interaction.last
        assert_equal "anthropic", interaction.provider
        assert_equal "claude-3-5-sonnet", interaction.model
        assert_equal 75, interaction.input_tokens
        assert_equal 30, interaction.output_tokens
      end

      test "extracts request text from messages" do
        RubyLLM.enable!

        ActiveSupport::Notifications.instrument("ruby_llm.request", {
          provider: "gemini",
          request: {
            "model" => "gemini-2.0-flash",
            "messages" => [
              { "content" => "Hello" },
              { "content" => "How are you?" }
            ]
          },
          response: {
            "content" => "I'm fine!",
            "model_id" => "gemini-2.0-flash",
            "input_tokens" => 10,
            "output_tokens" => 5
          },
          meta: { project: "demo" }
        })

        interaction = Interaction.last
        assert_equal "Hello\n\nHow are you?", interaction.request_text
        assert_equal "I'm fine!", interaction.response_text
      end

      test "stores metadata from meta hash" do
        RubyLLM.enable!

        ActiveSupport::Notifications.instrument("ruby_llm.request", {
          provider: "gemini",
          request: { "messages" => [ { "content" => "Hi" } ] },
          response: {
            "content" => "Hello!",
            "model_id" => "gemini-2.0-flash",
            "input_tokens" => 10,
            "output_tokens" => 5
          },
          meta: {
            project: "my-project",
            session_id: "session-123",
            latency_ms: 250,
            tags: %w[production important]
          }
        })

        interaction = Interaction.last
        assert_equal "my-project", interaction.project
        assert_equal "session-123", interaction.session_id
        assert_equal 250, interaction.latency_ms
        assert_equal %w[production important], interaction.tags
      end
    end
  end
end
