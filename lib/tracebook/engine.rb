module Tracebook
  class Engine < ::Rails::Engine
    isolate_namespace Tracebook

    initializer "tracebook.migrations" do |app|
      config.paths["db/migrate"].expanded.each do |path|
        app.config.paths["db/migrate"] << path
      end
    end
  end
end
