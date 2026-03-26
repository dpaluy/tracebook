module Tracebook
  class Engine < ::Rails::Engine
    isolate_namespace Tracebook

    initializer :append_migrations do |app|
      config.paths["db/migrate"].expanded.each do |expanded_path|
        app.config.paths["db/migrate"] << expanded_path unless app.config.paths["db/migrate"].include?(expanded_path)
      end
    end
  end
end
