require "test_helper"

module TraceBook
  class PersistInteractionJobTest < ActiveSupport::TestCase
    setup do
      clear_enqueued_jobs
      Interaction.delete_all
      RollupDaily.delete_all
      PricingRule.delete_all
      TraceBook.reset_configuration!
    end

    teardown do
      clear_enqueued_jobs
      Interaction.delete_all
      RollupDaily.delete_all
      PricingRule.delete_all
      TraceBook.reset_configuration!
    end

    test "persists interaction, computes cost, enqueues rollup" do
      PricingRule.create!(provider: "openai", model_glob: "gpt-*", input_cents_per_unit: 150, output_cents_per_unit: 600, effective_from: Date.today - 1)

      payload = TraceBook::NormalizedInteraction.new(
        provider: "openai",
        model: "gpt-4o",
        project: "demo",
        request_payload: { "messages" => [ { "content" => "Hello world" } ] },
        response_payload: { "content" => "Hi there" },
        request_text: "Hello world",
        response_text: "Hi there",
        input_tokens: 1200,
        output_tokens: 300,
        status: :success
      )

      assert_enqueued_with(job: Tracebook::DailyRollupsJob) do
        interaction = PersistInteractionJob.perform_now(payload.to_h)

        assert_equal "openai", interaction.provider
        assert_equal "demo", interaction.project
        assert_equal "Hello world", interaction.request_text
        assert_equal "Hi there", interaction.response_text
        assert_equal 180, interaction.cost_input_cents
        assert_equal 180, interaction.cost_output_cents
        assert_equal 360, interaction.cost_total_cents
      end
    end

    test "moves large payloads to active storage" do
      TraceBook.configure do |config|
        config.inline_payload_bytes = 16
        config.persist_async = false
      end

      large_text = "x" * 1024
      payload = TraceBook::NormalizedInteraction.new(
        provider: "openai",
        model: "gpt-4o",
        request_payload: { "content" => large_text },
        response_payload: { "content" => large_text }
      )

      interaction = PersistInteractionJob.perform_now(payload.to_h)

      assert_equal "active_storage", interaction.request_payload_store
      assert_not_nil interaction.request_payload_blob_id
      assert_equal "active_storage", interaction.response_payload_store
      assert_not_nil interaction.response_payload_blob_id
    end
  end
end
