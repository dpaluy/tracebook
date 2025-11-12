require "test_helper"

module TraceBook
  class ExportJobTest < ActiveSupport::TestCase
    setup do
      Interaction.delete_all
    end

    test "exports interactions to csv" do
      Interaction.create!(
        provider: "openai",
        model: "gpt-4o",
        project: "demo",
        status: :success,
        review_state: :pending,
        input_tokens: 100,
        output_tokens: 50,
        total_tokens: 150,
        cost_total_cents: 123,
        tags: [ "chat" ],
        metadata: { "env" => "test" }
      )

      blob = ExportJob.perform_now(format: :csv, filters: { provider: "openai" })

      assert_equal "text/csv", blob.content_type
      csv = blob.download
      assert_includes csv, "openai"
      assert_includes csv, "chat"
    end

    test "exports interactions to ndjson" do
      Interaction.create!(
        provider: "openai",
        model: "gpt-4o",
        status: :success,
        review_state: :pending
      )

      blob = ExportJob.perform_now(format: :ndjson)

      lines = blob.download.split("\n")
      assert_equal 1, lines.count
      parsed = JSON.parse(lines.first)
      assert_equal "openai", parsed["provider"]
    end
  end
end
