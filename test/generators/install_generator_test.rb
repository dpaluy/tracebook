# frozen_string_literal: true

require "test_helper"
require "rails/generators/test_case"
require "generators/tracebook/install/install_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests Tracebook::Generators::InstallGenerator
  destination File.expand_path("../../tmp", __dir__)

  setup do
    prepare_destination
  end

  test "creates initializer file" do
    run_generator

    assert_file "config/initializers/tracebook.rb" do |content|
      assert_match(/TraceBook\.configure/, content)
      assert_match(/config\.persist_async/, content)
    end
  end

  test "initializer contains adapter configuration options" do
    run_generator

    assert_file "config/initializers/tracebook.rb" do |content|
      assert_match(/auto_subscribe_ruby_llm/, content)
      assert_match(/auto_subscribe_active_agent/, content)
    end
  end
end
