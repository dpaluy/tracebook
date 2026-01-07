# frozen_string_literal: true

require_relative "redactors/patterns"

module Tracebook
  # Configuration object for TraceBook.
  #
  # Contains all configurable options for the TraceBook engine. Configuration
  # is frozen after the {Tracebook.configure} block executes to prevent
  # runtime modifications.
  #
  # @example Basic configuration
  #   TraceBook.configure do |config|
  #     config.project_name = "Support Console"
  #     config.persist_async = Rails.env.production?
  #     config.default_currency = "USD"
  #   end
  #
  # @example Pattern-based redaction DSL
  #   TraceBook.configure do |config|
  #     config.redact :email, :phone, :credit_card    # Enable specific patterns
  #     config.redact_group :api_keys                  # Enable pattern group
  #     config.redact_pattern(/secret=\w+/, "[SECRET]") # Custom pattern
  #   end
  #
  # @example Legacy custom redactors (lambdas)
  #   TraceBook.configure do |config|
  #     config.custom_redactors += [
  #       ->(payload) { payload.gsub(/api_key=\w+/, "api_key=[REDACTED]") }
  #     ]
  #   end
  #
  # @see Tracebook.configure
  class Config
    # @!attribute [rw] project_name
    #   @return [String, nil] Project identifier for this application (optional)
    #   Used to filter interactions by project in the dashboard
    attr_accessor :project_name

    # @!attribute [rw] persist_async
    #   @return [Boolean] Whether to persist interactions asynchronously (default: true)
    #   When true, {Tracebook.record!} enqueues {PersistInteractionJob}.
    #   When false, interactions are persisted inline.
    attr_accessor :persist_async

    # @!attribute [rw] inline_payload_bytes
    #   @return [Integer] Maximum payload size before spilling to ActiveStorage (default: 64KB)
    #   Payloads larger than this threshold are stored as ActiveStorage blobs
    #   instead of inline JSONB columns.
    attr_accessor :inline_payload_bytes

    # @!attribute [rw] default_currency
    #   @return [String] Currency code for cost calculations (default: "USD")
    #   Used in {PricingRule} cost tracking
    attr_accessor :default_currency

    # @!attribute [rw] export_formats
    #   @return [Array<Symbol>] Available export formats (default: [:csv, :ndjson])
    #   Supported formats for {ExportJob}
    attr_accessor :export_formats

    # @!attribute [rw] redactors
    #   @return [Array<Redactor>] Built-in PII redactors
    #   Default redactors for email, phone, credit card numbers.
    #   See {Redactors::Email}, {Redactors::Phone}, {Redactors::CardPAN}
    attr_accessor :redactors

    # @!attribute [rw] custom_redactors
    #   @return [Array<Proc>] Custom redaction lambdas
    #   Additional user-defined redactors that receive the payload string
    #   and return a redacted version.
    #   @example
    #     config.custom_redactors += [
    #       ->(payload) { payload.gsub(/secret=\w+/, "secret=[REDACTED]") }
    #     ]
    attr_accessor :custom_redactors

    # @!attribute [rw] auto_subscribe_ruby_llm
    #   @return [Boolean] Auto-enable RubyLLM adapter on boot (default: false)
    attr_accessor :auto_subscribe_ruby_llm

    # @!attribute [rw] auto_subscribe_active_agent
    #   @return [Boolean] Auto-enable ActiveAgent adapter on boot (default: false)
    attr_accessor :auto_subscribe_active_agent

    # @!attribute [rw] per_page
    #   @return [Integer] Number of interactions per page in dashboard (default: 100)
    attr_accessor :per_page

    # @!attribute [rw] actor_display
    #   @return [Proc, nil] Lambda to format actor display name
    #   Receives the actor record and returns a display string.
    #   When nil, falls back to common methods (:name, :email, :title, :display_name, :username)
    #   @example
    #     config.actor_display = ->(actor) { "#{actor.class.name} - #{actor.email}" }
    #   @example
    #     config.actor_display = ->(actor) { actor.full_name }
    attr_accessor :actor_display

    # @!attribute [rw] llm_redactor
    #   @return [Redactors::LLMBased, nil] Optional LLM-based redactor for advanced PII detection
    #   When configured, can be used for async LLM redaction via {LLMRedactionJob}.
    #   @example Configure with OpenAI
    #     config.llm_redactor = Tracebook::Redactors::LLMBased.new(
    #       provider: :openai,
    #       model: "gpt-4o-mini",
    #       mode: :sync,
    #       on_failure: :log_and_continue
    #     )
    #   @example Configure with local Ollama (privacy-preserving)
    #     config.llm_redactor = Tracebook::Redactors::LLMBased.new(
    #       provider: :ollama,
    #       model: "llama3.2"
    #     )
    attr_accessor :llm_redactor

    # @!attribute [r] enabled_patterns
    #   @return [Array<Symbol>] Pattern symbols enabled via redact DSL
    attr_reader :enabled_patterns

    # @!attribute [r] custom_patterns
    #   @return [Array<Redactors::Pattern>] Custom patterns added via redact_pattern
    attr_reader :custom_patterns

    # Creates a new configuration with default values.
    #
    # @return [Config]
    def initialize
      @project_name = nil
      @persist_async = true
      @inline_payload_bytes = 64 * 1024
      @default_currency = "USD"
      @export_formats = [ :csv, :ndjson ]
      @redactors = default_redactors
      @custom_redactors = []
      @auto_subscribe_ruby_llm = false
      @auto_subscribe_active_agent = false
      @per_page = 100
      @actor_display = nil
      @llm_redactor = nil
      @enabled_patterns = []
      @custom_patterns = []
    end

    # Enable one or more built-in redaction patterns.
    #
    # @param names [Array<Symbol>] Pattern names from {Redactors::PATTERNS}
    # @raise [ConfigurationError] if any name is not a valid pattern
    # @return [void]
    #
    # @example Enable email and phone redaction
    #   config.redact :email, :phone
    #
    # @example Enable financial PII
    #   config.redact :credit_card, :ssn
    def redact(*names)
      names.each do |name|
        unless Redactors::PATTERNS.key?(name)
          valid_patterns = Redactors::PATTERNS.keys.join(", ")
          raise ConfigurationError, "Unknown pattern: #{name}. Valid patterns: #{valid_patterns}"
        end
        @enabled_patterns << name unless @enabled_patterns.include?(name)
      end
    end

    # Enable a group of related patterns.
    #
    # @param group_name [Symbol] Group name from {Redactors::PATTERN_GROUPS}
    # @raise [ConfigurationError] if group name is not valid
    # @return [void]
    #
    # @example Enable all API key patterns
    #   config.redact_group :api_keys
    #
    # @see Redactors::PATTERN_GROUPS
    def redact_group(group_name)
      unless Redactors::PATTERN_GROUPS.key?(group_name)
        valid_groups = Redactors::PATTERN_GROUPS.keys.join(", ")
        raise ConfigurationError, "Unknown pattern group: #{group_name}. Valid groups: #{valid_groups}"
      end

      Redactors::PATTERN_GROUPS[group_name].each do |pattern_name|
        @enabled_patterns << pattern_name unless @enabled_patterns.include?(pattern_name)
      end
    end

    # Add a custom regex pattern for redaction.
    #
    # @param regex [Regexp] The pattern to match
    # @param replacement [String] The replacement text (e.g., "[REDACTED]")
    # @param name [String] Name for audit trail (defaults to "custom_N")
    # @return [void]
    #
    # @example Redact custom API keys
    #   config.redact_pattern(/myapp_key_\w+/, "[MYAPP_KEY]")
    #
    # @example Named custom pattern
    #   config.redact_pattern(/secret=\w+/, "[SECRET]", name: "app_secret")
    def redact_pattern(regex, replacement, name: nil)
      pattern_name = name || "custom_#{@custom_patterns.size + 1}"
      pattern = Redactors::Pattern.new(
        regex: regex,
        replacement: replacement,
        name: pattern_name
      )
      @custom_patterns << pattern
    end

    # Returns all enabled Pattern objects for redaction.
    #
    # Combines patterns enabled via {#redact} and {#redact_group}
    # with custom patterns from {#redact_pattern}.
    #
    # @return [Array<Redactors::Pattern>]
    def active_patterns
      patterns = @enabled_patterns.map { |name| Redactors::PATTERNS[name] }
      patterns + @custom_patterns
    end

    # Returns true if configuration has been finalized.
    #
    # @return [Boolean]
    def finalized?
      @finalized == true
    end

    # Freezes the configuration to prevent further changes.
    #
    # Called automatically by {Tracebook.configure} after the block executes.
    #
    # @return [void]
    def finalize!
      return if finalized?

      @finalized = true
      freeze_collections!
      freeze
    end

    private

    def default_redactors
      # TODO: Replace with new Pattern-based redactors from T3/T7
      []
    end

    def freeze_collections!
      @redactors = @redactors.map { |redactor| redactor }.freeze
      @custom_redactors = @custom_redactors.map { |callable| callable }.freeze
      @export_formats = @export_formats.map(&:to_sym).freeze
      @enabled_patterns = @enabled_patterns.dup.freeze
      @custom_patterns = @custom_patterns.dup.freeze
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
