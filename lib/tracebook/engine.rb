module Tracebook
  class Engine < ::Rails::Engine
    isolate_namespace Tracebook

    initializer :append_migrations do |app|
      # Skip if running within the engine itself (e.g., dummy app)
      unless app.root.to_s.match?(root.to_s)
        config.paths["db/migrate"].expanded.each do |expanded_path|
          app.config.paths["db/migrate"] << expanded_path
        end
      end
    end
  end
end
