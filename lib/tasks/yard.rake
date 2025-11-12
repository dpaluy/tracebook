# frozen_string_literal: true

begin
  require "yard"

  YARD::Rake::YardocTask.new(:yard) do |t|
    t.files = [ "lib/**/*.rb", "app/**/*.rb" ]
    t.options = [
      "--markup", "markdown",
      "--markup-provider", "kramdown",
      "--readme", "README.md",
      "--output-dir", "doc",
      "--protected",
      "--private"
    ]
  end

  desc "Generate YARD documentation and open in browser"
  task "yard:open" => :yard do
    system "open doc/index.html"
  end

  desc "Generate YARD stats"
  task "yard:stats" do
    sh "yard stats --list-undoc"
  end
rescue LoadError
  # YARD not available
end
