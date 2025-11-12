require "bundler/setup"

APP_RAKEFILE = File.expand_path("test/dummy/Rakefile", __dir__)
load "rails/tasks/engine.rake"

require "bundler/gem_tasks"

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.verbose = false
end

task :prepare_test_db do
  ENV["RAILS_ENV"] = "test"
  Rake::Task["app:db:prepare"].invoke
end

task default: [ :prepare_test_db, :test ]
