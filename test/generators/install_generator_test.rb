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
      assert_match(/Tracebook\.configure/, content)
      assert_match(/chat_class/, content)
      assert_match(/message_class/, content)
    end
  end

  test "initializer contains configuration options" do
    run_generator

    assert_file "config/initializers/tracebook.rb" do |content|
      assert_match(/default_currency/, content)
      assert_match(/actor_display/, content)
      assert_match(/per_page/, content)
    end
  end
end
