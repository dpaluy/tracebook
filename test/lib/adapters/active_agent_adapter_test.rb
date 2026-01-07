require "test_helper"

module TraceBook
  module Adapters
    class ActiveAgentAdapterTest < ActiveSupport::TestCase
      class FakeBus
        def initialize
          @subscribers = []
        end

        def subscribe(&block)
          @subscribers << block
          block
        end

        def publish(event)
          @subscribers.each { |subscriber| subscriber.call(event) }
        end
      end

      setup do
        Interaction.delete_all
        TraceBook.reset_configuration!
        TraceBook.configure do |config|
          config.persist_async = false
        end
        @bus = FakeBus.new
      end

      teardown do
        TraceBook.reset_configuration!
        Interaction.delete_all
      end

      test "records events published by active agent bus" do
        ActiveAgent.enable!(bus: @bus)

        @bus.publish(
          provider: "openai",
          request: { "model" => "gpt-4o", "messages" => [ { "content" => "Plan" } ] },
          response: {
            "content" => "Step",
            "model_id" => "gpt-4o",
            "input_tokens" => 10,
            "output_tokens" => 5
          },
          meta: { project: "demo", tags: [ "agent" ] },
          session_id: "session-1"
        )

        assert_equal 1, Interaction.count
        interaction = Interaction.first
        assert_equal "openai", interaction.provider
        assert_equal "session-1", interaction.session_id
        assert_equal [ "agent" ], interaction.tags
        assert_equal 10, interaction.input_tokens
        assert_equal 5, interaction.output_tokens
      end
    end
  end
end
