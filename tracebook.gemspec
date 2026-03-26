require_relative "lib/tracebook/version"

Gem::Specification.new do |spec|
  spec.name        = "tracebook"
  spec.version     = Tracebook::VERSION
  spec.authors     = [ "dpaluy" ]
  spec.email       = [ "dpaluy@users.noreply.github.com" ]

  spec.summary     = "Cost tracking and review dashboard for RubyLLM conversations."
  spec.description = "Tracebook is a Rails engine that adds cost tracking, review workflows, and a dashboard UI " \
                     "on top of RubyLLM's Chat and Message models. Features include per-message cost calculation " \
                     "with configurable pricing rules, chat-level approval workflows, and a Hotwire-powered dashboard."
  spec.homepage    = "https://github.com/dpaluy/tracebook"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.4.0"

  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/tracebook"
  spec.metadata["source_code_uri"] = "https://github.com/dpaluy/tracebook"
  spec.metadata["changelog_uri"] = "https://github.com/dpaluy/tracebook/blob/master/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/dpaluy/tracebook/issues"

  # Specify which files should be added to the gem when it is released
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile test/ .github/ .rubocop.yml .gitignore .worktrees/ .repoprompt/])
    end
  end

  spec.require_paths = [ "lib" ]

  # Include documentation files
  spec.extra_rdoc_files = Dir["README.md", "MIT-LICENSE"]

  spec.add_dependency "rails", ">= 8.1.1"
  spec.add_dependency "turbo-rails", ">= 2.0.0"
  spec.add_dependency "stimulus-rails", ">= 1.3"
  spec.add_dependency "pagy", ">= 43.0"
end
