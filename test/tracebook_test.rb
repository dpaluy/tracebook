require "test_helper"

class TracebookTest < ActiveSupport::TestCase
  test "it has a version number" do
    assert Tracebook::VERSION
  end

  test "serialize_actor returns empty hash for nil" do
    assert_equal({}, Tracebook.serialize_actor(nil))
  end

  test "serialize_actor extracts global_id when available" do
    global_id = Object.new
    global_id.define_singleton_method(:to_s) { "gid://app/User/123" }

    actor = Object.new
    actor.define_singleton_method(:to_global_id) { global_id }

    result = Tracebook.serialize_actor(actor)

    assert_equal({ actor_gid: "gid://app/User/123" }, result)
  end

  test "serialize_actor falls back to type/id tuple when no global_id" do
    actor_class = Class.new do
      def self.name
        "CustomActor"
      end
    end

    actor = actor_class.new
    actor.define_singleton_method(:respond_to?) do |method|
      method != :to_global_id && super(method)
    end
    actor.define_singleton_method(:id) { 456 }

    result = Tracebook.serialize_actor(actor)

    assert_equal({ actor_type: "CustomActor", actor_id: 456 }, result)
  end

  test "serialize_actor returns empty hash for non-serializable objects" do
    actor = Object.new

    result = Tracebook.serialize_actor(actor)

    assert_equal({}, result)
  end

  # T10: Redaction timing tests

  test "record! redacts PII before job enqueue with sync mode" do
    TraceBook.reset_configuration!
    Tracebook::Interaction.delete_all
    TraceBook.configure do |config|
      config.redact :email
      config.persist_async = false  # Test with sync mode to verify result
    end

    result = TraceBook.record!(
      provider: "openai",
      model: "gpt-4o",
      request_text: "Contact user@example.com",
      response_text: "OK"
    )

    interaction = result.interaction
    assert_not_nil interaction
    assert_equal "Contact [EMAIL]", interaction.request_text
    assert_not_includes interaction.request_text.to_s, "user@example.com"
  ensure
    TraceBook.reset_configuration!
    Tracebook::Interaction.delete_all
  end

  test "record! no PII in persisted data with patterns enabled" do
    TraceBook.reset_configuration!
    Tracebook::Interaction.delete_all
    TraceBook.configure do |config|
      config.redact :email, :phone
      config.persist_async = false
    end

    result = TraceBook.record!(
      provider: "openai",
      model: "gpt-4o",
      request_payload: {
        "messages" => [
          { "content" => "Email: test@email.org, Phone: (555) 123-4567" }
        ]
      },
      response_payload: {}
    )

    # Verify no PII in persisted interaction
    interaction = result.interaction
    payload_json = interaction.request_payload.to_json
    assert_not_includes payload_json, "test@email.org"
    assert_includes payload_json, "[EMAIL]"
    assert_includes payload_json, "[PHONE]"
  ensure
    TraceBook.reset_configuration!
    Tracebook::Interaction.delete_all
  end

  test "record! serializes actor for job-safe persistence" do
    TraceBook.reset_configuration!
    Tracebook::Interaction.delete_all
    TraceBook.configure do |config|
      config.persist_async = false
    end

    actor_class = Class.new do
      def self.name
        "TestActor"
      end
    end
    actor = actor_class.new
    actor.define_singleton_method(:id) { 789 }
    actor.define_singleton_method(:respond_to?) do |method|
      method != :to_global_id && super(method)
    end

    result = TraceBook.record!(
      provider: "openai",
      model: "gpt-4o",
      request_text: "Hello",
      response_text: "Hi",
      actor: actor
    )

    # Actor should be serialized as type/id in the interaction
    interaction = result.interaction
    assert_equal "TestActor", interaction.actor_type
    assert_equal 789, interaction.actor_id
  ensure
    TraceBook.reset_configuration!
    Tracebook::Interaction.delete_all
  end

  test "record! redaction performance is acceptable" do
    TraceBook.reset_configuration!
    Tracebook::Interaction.delete_all
    TraceBook.configure do |config|
      config.redact :email, :phone, :credit_card, :ssn
      config.persist_async = false
    end

    # Create payload with many fields to redact
    large_payload = {
      "messages" => 50.times.map do |i|
        { "content" => "Email #{i}: user#{i}@test.com, Phone: (555) 123-45#{i.to_s.rjust(2, '0')}" }
      end
    }

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    result = TraceBook.record!(
      provider: "openai",
      model: "gpt-4o",
      request_payload: large_payload,
      response_payload: {}
    )

    elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000

    # Performance should be under 100ms for regex redaction (database write adds overhead)
    assert elapsed_ms < 100, "Redaction took #{elapsed_ms.round(2)}ms, should be under 100ms"

    # Verify redaction actually happened
    assert_not_includes result.interaction.request_payload.to_json, "@test.com"
  ensure
    TraceBook.reset_configuration!
    Tracebook::Interaction.delete_all
  end
end
