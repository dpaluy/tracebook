# frozen_string_literal: true

require "test_helper"

module TraceBook
  class ExportsControllerTest < ActionDispatch::IntegrationTest
    include Tracebook::Engine.routes.url_helpers

    fixtures "tracebook/interactions"

    setup do
      @routes = Tracebook::Engine.routes
      @interaction = tracebook_interactions(:openai_gpt4o)
    end

    test "creates CSV export" do
      post exports_path(format: :csv)

      assert_redirected_to %r{/tracebook/exports/}
      assert_equal "Export ready", flash[:notice]
    end

    test "creates CSV export with filters" do
      post exports_path(format: :csv, filters: { provider: "openai" })

      assert_redirected_to %r{/tracebook/exports/}
    end

    test "creates NDJSON export" do
      post exports_path(format: :ndjson)

      assert_redirected_to %r{/tracebook/exports/}
    end

    test "downloads exported CSV file" do
      post exports_path(format: :csv)

      # Follow redirect to download
      follow_redirect!
      assert_response :success
      assert_equal "text/csv", response.content_type
      assert_match(/tracebook-export-.*\.csv/, response.headers["Content-Disposition"])

      # Verify CSV content includes header and data
      assert_match "timestamp", response.body
      assert_match "provider", response.body
      assert_match "openai", response.body
    end

    test "downloads exported NDJSON file" do
      post exports_path(format: :ndjson)

      follow_redirect!
      assert_response :success
      assert_equal "application/x-ndjson", response.content_type

      # Verify NDJSON content - each line is a JSON object
      lines = response.body.split("\n")
      assert lines.any?, "Should have at least one line"
      json = JSON.parse(lines.first)
      assert_includes %w[openai anthropic], json["provider"]
    end

    test "returns 404 for invalid signed id" do
      get export_path("invalid-signed-id")

      assert_response :not_found
    end
  end
end
