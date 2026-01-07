# frozen_string_literal: true

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
  # @example With custom redactors
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
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
