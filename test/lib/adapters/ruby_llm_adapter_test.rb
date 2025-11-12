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
    end
  end
end
