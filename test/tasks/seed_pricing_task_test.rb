# frozen_string_literal: true

require "test_helper"
require "rake"

class SeedPricingTaskTest < ActiveSupport::TestCase
  setup do
    Tracebook::PricingRule.delete_all
    Rails.application.load_tasks unless Rake::Task.task_defined?("tracebook:seed_pricing")
  end

  test "tracebook:seed_pricing task exists" do
    assert Rake::Task.task_defined?("tracebook:seed_pricing")
  end

  test "task creates pricing rules" do
    assert_difference "Tracebook::PricingRule.count", 10 do
      capture_io { Rake::Task["tracebook:seed_pricing"].invoke }
    end
  end

  teardown do
    Rake::Task["tracebook:seed_pricing"].reenable
  end
end
