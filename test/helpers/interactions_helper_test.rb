require "test_helper"

module TraceBook
  class InteractionsHelperTest < ActionView::TestCase
    include Tracebook::InteractionsHelper

    test "formatted_payload renders hash as pretty json" do
      json = formatted_payload({ "foo" => "bar" }, "fallback")

      assert_includes json, "\n"
      assert_includes json, "foo"
    end

    test "formatted_payload falls back to text when payload is nil" do
      assert_equal "fallback", formatted_payload(nil, "fallback")
    end

    test "payload_for returns inline payload when present" do
      interaction = Interaction.create!(
        provider: "openai",
        model: "gpt-4o",
        status: :success,
        review_state: :pending,
        request_payload: { "foo" => "bar" }
      )

      assert_equal({ "foo" => "bar" }, payload_for(interaction, :request))
    end

    test "review_badge renders approved with success style" do
      result = review_badge("approved")

      assert_includes result, "tb-status-success"
      assert_includes result, "approved"
    end

    test "review_badge renders flagged with warning style" do
      result = review_badge("flagged")

      assert_includes result, "tb-status-warning"
      assert_includes result, "flagged"
    end

    test "review_badge renders rejected with error style" do
      result = review_badge("rejected")

      assert_includes result, "tb-status-error"
      assert_includes result, "rejected"
    end

    test "review_badge renders pending with pending style" do
      result = review_badge("pending")

      assert_includes result, "tb-status-pending"
      assert_includes result, "pending"
    end
  end
end
