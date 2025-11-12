require_relative "lib/tracebook/version"

Gem::Specification.new do |spec|
  spec.name        = "tracebook"
  spec.version     = Tracebook::VERSION
  spec.authors     = [ "dpaluy" ]
  spec.email       = [ "dpaluy@users.noreply.github.com" ]

  spec.summary     = "Rails engine for LLM interaction telemetry and review."
  spec.description = "TraceBook provides a Rails engine for capturing, storing, and reviewing LLM API interactions " \
                     "with built-in support for OpenAI, Anthropic, and Ollama. Features include PII redaction, " \
                     "cost tracking, review workflows, and export capabilities."
  spec.homepage    = "https://github.com/dpaluy/tracebook"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/tracebook"
  spec.metadata["source_code_uri"] = "https://github.com/dpaluy/tracebook"
  spec.metadata["changelog_uri"] = "https://github.com/dpaluy/tracebook/blob/main/CHANGELOG.md"
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
  spec.add_dependency "csv", "~> 3.3"
end
