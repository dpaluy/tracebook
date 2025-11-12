require "test_helper"

module TraceBook
  class RedactionRuleTest < ActiveSupport::TestCase
    test "requires name and pattern" do
      rule = RedactionRule.new

      assert_not rule.valid?
      assert_includes rule.errors.attribute_names, :name
      assert_includes rule.errors.attribute_names, :pattern
    end
  end
end
