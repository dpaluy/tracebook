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

    test "review_badge renders pending with pending style" do
      result = review_badge("pending")

      assert_includes result, "tb-status-pending"
      assert_includes result, "pending"
    end

    test "latency_display returns dash for nil" do
      assert_equal "—", latency_display(nil)
    end

    test "latency_display shows milliseconds for values under 1000" do
      assert_equal "500ms", latency_display(500)
      assert_equal "999ms", latency_display(999)
    end

    test "latency_display shows seconds for values 1000 and above" do
      assert_equal "1.0s", latency_display(1000)
      assert_equal "2.5s", latency_display(2500)
      assert_equal "10.25s", latency_display(10250)
    end

    test "token_breakdown formats input and output tokens" do
      interaction = Interaction.new(input_tokens: 1000, output_tokens: 500)
      assert_equal "1,000 / 500", token_breakdown(interaction)
    end

    test "token_breakdown handles nil tokens" do
      interaction = Interaction.new(input_tokens: nil, output_tokens: nil)
      assert_equal "0 / 0", token_breakdown(interaction)
    end

    test "actor_type_options returns demodulized display names" do
      types = [ "ActiveRecord::User", "Project" ]
      options = actor_type_options(types)

      assert_equal [ [ "User", "ActiveRecord::User" ], [ "Project", "Project" ] ], options
    end

    test "actor_link returns dash for blank actor_id" do
      interaction = Interaction.new(actor_id: nil)
      assert_equal "—", actor_link(interaction)
    end

    test "fallback_actor_display shows type and id" do
      interaction = Interaction.new(actor_type: "ActiveRecord::User", actor_id: 123)
      result = fallback_actor_display(interaction)

      assert_includes result, "User#123"
      assert_includes result, "tb-muted"
    end
  end
end
