# frozen_string_literal: true

require "rails/generators/base"

module Tracebook
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Install TraceBook: copy migrations and create initializer"

      def copy_migrations
        rake "tracebook:install:migrations"
      end

      def create_initializer
        template "initializer.rb.tt", "config/initializers/tracebook.rb"
      end

      def show_next_steps
        say ""
        say "TraceBook installed!", :green
        say ""
        say "Next steps:"
        say "  1. Run migrations:  bin/rails db:migrate"
        say "  2. Mount the engine in config/routes.rb:"
        say ""
        say "     mount TraceBook::Engine => \"/tracebook\""
        say ""
        say "  3. Configure authorization in config/initializers/tracebook.rb"
        say "  4. Set up ActiveRecord encryption (see README)"
        say ""
      end
    end
  end
end
