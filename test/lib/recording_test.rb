require "test_helper"

module TraceBook
  class RecordingTest < ActiveSupport::TestCase
    setup do
      clear_enqueued_jobs
      clear_performed_jobs
      TraceBook.reset_configuration!
    end

    teardown do
      clear_enqueued_jobs
      clear_performed_jobs
      TraceBook.reset_configuration!
      Interaction.delete_all
    end

    test "records interactions asynchronously by default" do
      TraceBook.configure do |config|
        config.persist_async = true
      end

      assert_enqueued_with(job: Tracebook::PersistInteractionJob) do
        result = TraceBook.record!(provider: "openai", model: "gpt-4o", project: "demo", request: { message: "hi" }, response: { content: "hello" })
        assert result.success?
        assert_nil result.interaction
      end
    end

    test "persists immediately when persist_async is false" do
      TraceBook.configure do |config|
        config.persist_async = false
      end

      assert_difference -> { Interaction.count }, 1 do
        result = TraceBook.record!(provider: "openai", model: "gpt-4o", project: "demo", request: { message: "hi" }, response: { content: "hello" }, input_tokens: 12, output_tokens: 8, latency_ms: 35)
        assert result.success?
        assert_not_nil result.interaction
        assert_equal "openai", result.interaction.provider
        assert_equal "gpt-4o", result.interaction.model
        assert_equal 20, result.interaction.total_tokens
      end
    end
  end
end
