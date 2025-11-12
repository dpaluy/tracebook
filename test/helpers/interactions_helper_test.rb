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
  end
end
