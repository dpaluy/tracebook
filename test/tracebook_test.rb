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
end
