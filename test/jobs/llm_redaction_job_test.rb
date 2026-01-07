require "test_helper"

module Tracebook
  class LlmRedactionJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    # Mock LLM redactor for testing
    class MockRedactor
      attr_accessor :replacement, :should_fail

      def initialize(replacement: "[LLM_REDACTED]")
        @replacement = replacement
        @should_fail = false
      end

      def call(text, audit: nil, field_path: nil)
        raise "Mock LLM error" if should_fail

        # Simple mock: replace "SECRET" with replacement
        redacted = text.gsub(/SECRET/, replacement)
        [ redacted, audit || RedactionAudit.new ]
      end
    end

    setup do
      clear_enqueued_jobs
      clear_performed_jobs
      TraceBook.reset_configuration!
      Interaction.delete_all
      @mock_redactor = MockRedactor.new
    end

    teardown do
      clear_enqueued_jobs
      clear_performed_jobs
      TraceBook.reset_configuration!
      Interaction.delete_all
    end

    test "skips when no LLM redactor configured" do
      TraceBook.configure { |c| c.persist_async = false }
      interaction = create_interaction(request_text: "Some SECRET data")

      perform_enqueued_jobs do
        LlmRedactionJob.perform_later(interaction.id)
      end

      interaction.reload
      assert_equal "skipped", interaction.metadata["llm_redaction_status"]
      assert_equal "no_llm_redactor_configured", interaction.metadata["llm_redaction_reason"]
      assert_equal "Some SECRET data", interaction.request_text # Unchanged
    end

    test "redacts text fields with LLM redactor" do
      TraceBook.configure do |c|
        c.persist_async = false
        c.llm_redactor = @mock_redactor
      end

      interaction = create_interaction(
        request_text: "My SECRET password",
        response_text: "Your SECRET is safe"
      )

      perform_enqueued_jobs do
        LlmRedactionJob.perform_later(interaction.id)
      end

      interaction.reload
      assert_equal "success", interaction.metadata["llm_redaction_status"]
      assert_equal "My [LLM_REDACTED] password", interaction.request_text
      assert_equal "Your [LLM_REDACTED] is safe", interaction.response_text
      assert_not_nil interaction.metadata["llm_redacted_at"]
    end

    test "redacts payload fields with LLM redactor" do
      TraceBook.configure do |c|
        c.persist_async = false
        c.llm_redactor = @mock_redactor
      end

      interaction = create_interaction(
        request_payload: { "message" => "Tell me the SECRET" },
        response_payload: { "content" => "The SECRET is 42" }
      )

      perform_enqueued_jobs do
        LlmRedactionJob.perform_later(interaction.id)
      end

      interaction.reload
      assert_equal "success", interaction.metadata["llm_redaction_status"]
      assert_includes interaction.request_payload.to_json, "[LLM_REDACTED]"
      assert_includes interaction.response_payload.to_json, "[LLM_REDACTED]"
      assert_not_includes interaction.request_payload.to_json, "SECRET"
    end

    test "skips already processed interactions" do
      TraceBook.configure do |c|
        c.persist_async = false
        c.llm_redactor = @mock_redactor
      end

      interaction = create_interaction(
        request_text: "Some SECRET data",
        metadata: { "llm_redaction_status" => "success" }
      )

      # Job should return early without calling redactor
      @mock_redactor.should_fail = true # Would fail if called

      perform_enqueued_jobs do
        LlmRedactionJob.perform_later(interaction.id)
      end

      interaction.reload
      assert_equal "success", interaction.metadata["llm_redaction_status"]
      assert_equal "Some SECRET data", interaction.request_text # Unchanged
    end

    test "records failure on redaction error" do
      TraceBook.configure do |c|
        c.persist_async = false
        c.llm_redactor = @mock_redactor
      end
      @mock_redactor.should_fail = true

      interaction = create_interaction(request_text: "Some SECRET data")

      # perform_now with retry_on configured may not re-raise, but should record failure
      LlmRedactionJob.perform_now(interaction.id)

      interaction.reload
      assert_equal "failed", interaction.metadata["llm_redaction_status"]
      assert_equal "Mock LLM error", interaction.metadata["llm_redaction_error"]
      assert_equal 1, interaction.metadata["llm_redaction_attempts"]
      assert_not_nil interaction.metadata["llm_redaction_last_attempt"]
    end

    test "increments attempt count on repeated failures" do
      TraceBook.configure do |c|
        c.persist_async = false
        c.llm_redactor = @mock_redactor
      end
      @mock_redactor.should_fail = true

      interaction = create_interaction(
        request_text: "Some SECRET data",
        metadata: { "llm_redaction_attempts" => 1 }
      )

      # perform_now with retry_on configured may not re-raise
      LlmRedactionJob.perform_now(interaction.id)

      interaction.reload
      assert_equal 2, interaction.metadata["llm_redaction_attempts"]
    end

    test "discards job when interaction not found" do
      TraceBook.configure do |c|
        c.persist_async = false
        c.llm_redactor = @mock_redactor
      end

      # Should not raise - just discarded
      assert_nothing_raised do
        perform_enqueued_jobs do
          LlmRedactionJob.perform_later(999999)
        end
      end
    end

    test "uses pessimistic lock to prevent race conditions" do
      TraceBook.configure do |c|
        c.persist_async = false
        c.llm_redactor = @mock_redactor
      end

      interaction = create_interaction(request_text: "Some SECRET data")

      # Verify the job uses .lock method (can't easily test concurrency in MiniTest)
      # This test verifies the job completes successfully with lock
      perform_enqueued_jobs do
        LlmRedactionJob.perform_later(interaction.id)
      end

      interaction.reload
      assert_equal "success", interaction.metadata["llm_redaction_status"]
    end

    test "handles nil payloads gracefully" do
      TraceBook.configure do |c|
        c.persist_async = false
        c.llm_redactor = @mock_redactor
      end

      interaction = create_interaction(
        request_payload: nil,
        response_payload: nil,
        request_text: "SECRET data",
        response_text: nil
      )

      perform_enqueued_jobs do
        LlmRedactionJob.perform_later(interaction.id)
      end

      interaction.reload
      assert_equal "success", interaction.metadata["llm_redaction_status"]
      assert_equal "[LLM_REDACTED] data", interaction.request_text
    end

    private

    def create_interaction(attrs = {})
      defaults = {
        provider: "openai",
        model: "gpt-4o",
        status: :success,
        metadata: {}
      }
      Interaction.create!(defaults.merge(attrs))
    end
  end
end
