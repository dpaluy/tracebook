require "test_helper"

module TraceBook
  class PricingRuleTest < ActiveSupport::TestCase
    test "requires provider, model_glob, and effective_from" do
      rule = PricingRule.new

      assert_not rule.valid?
      assert_includes rule.errors.attribute_names, :provider
      assert_includes rule.errors.attribute_names, :model_glob
      assert_includes rule.errors.attribute_names, :effective_from
    end
  end
end
