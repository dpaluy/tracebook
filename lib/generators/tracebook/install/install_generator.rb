# frozen_string_literal: true

require "rails/generators/base"

module Tracebook
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Install Tracebook: create initializer"

      def create_initializer
        template "initializer.rb.tt", "config/initializers/tracebook.rb"
      end

      def show_next_steps
        say ""
        say "Tracebook installed!", :green
        say ""
        say "Next steps:"
        say "  1. Run migrations:  bin/rails db:migrate"
        say "  2. Mount the engine in config/routes.rb:"
        say ""
        say "     mount Tracebook::Engine => \"/tracebook\""
        say ""
        say "  3. Seed default pricing:  bin/rails tracebook:seed_pricing"
        say "  4. Call Tracebook.calculate_cost! after LLM responses"
        say "     (see README for integration examples)"
        say ""
      end
    end
  end
end
