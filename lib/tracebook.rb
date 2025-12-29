require "pagy"
require "tracebook/version"
require "tracebook/engine"
require "tracebook/errors"
require "tracebook/redactors"
require "tracebook/mappers"
require "tracebook/config"
require "tracebook/result"
require "tracebook/normalized_interaction"
require "tracebook/redaction_pipeline"
require "tracebook/pricing"
require "tracebook/adapters"

# TraceBook is a Rails engine for capturing, storing, and reviewing LLM interactions.
#
# It provides:
# - Automatic redaction of PII from request/response payloads
# - Encrypted storage of sensitive data using ActiveRecord::Encryption
# - Cost tracking based on token usage and configurable pricing rules
# - Review workflow (approve/flag/reject) with audit trail
# - Hotwire-powered dashboard UI with filtering and export
# - Built-in adapters for OpenAI, Anthropic, Ollama
# - Support for hierarchical agent sessions (parent-child relationships)
#
# @example Basic configuration
#   TraceBook.configure do |config|
#     config.authorize = ->(user, action, resource) { user&.admin? }
#     config.project_name = "My App"
#     config.persist_async = Rails.env.production?
#   end
#
# @example Recording an interaction
#   TraceBook.record!(
#     provider: "openai",
#     model: "gpt-4o",
#     request_payload: { messages: messages },
#     response_payload: response,
#     input_tokens: 100,
#     output_tokens: 50,
#     trackable: current_user,
#     tags: ["production", "support"]
#   )
#
# @see https://github.com/dpaluy/tracebook README for full documentation
module Tracebook
  class << self
    # Returns the current configuration instance.
    #
    # @return [Tracebook::Config] the configuration object
    def config
      @config ||= Config.new
    end

    # Configures TraceBook with a block.
    #
    # Configuration is frozen after the block executes. Call {#reset_configuration!}
    # in tests to reset.
    #
    # @yield [config] Yields the config object for modification
    # @yieldparam config [Tracebook::Config] the configuration object
    # @return [Tracebook::Config] the finalized configuration
    # @raise [ConfigurationError] if configuration is already finalized
    #
    # @example
    #   TraceBook.configure do |config|
    #     config.authorize = ->(user, action, resource) { user&.admin? }
    #     config.persist_async = true
    #     config.project_name = "Support App"
    #   end
    def configure
      ensure_configurable!

      yield(config)
      finalize_configuration!
      config
    end

    # Resets configuration to a clean state.
    #
    # Used in tests to start with fresh configuration between test cases.
    #
    # @return [void]
    #
    # @example In test setup
    #   setup do
    #     TraceBook.reset_configuration!
    #     TraceBook.configure do |config|
    #       config.authorize = ->(*) { true }
    #     end
    #   end
    def reset_configuration!
      @config = Config.new
      @configuration_finalized = false
    end

    # Records an LLM interaction.
    #
    # When `config.persist_async` is true, the interaction is enqueued via
    # {PersistInteractionJob}. Otherwise, it's persisted inline.
    #
    # @param attributes [Hash] Interaction attributes
    # @option attributes [String] :provider Provider name (e.g., "openai", "anthropic") **required**
    # @option attributes [String] :model Model identifier (e.g., "gpt-4o", "claude-3-5-sonnet") **required**
    # @option attributes [String, nil] :project Project name for filtering
    # @option attributes [Hash, nil] :request_payload Full request sent to provider (will be encrypted)
    # @option attributes [Hash, nil] :response_payload Full response from provider (will be encrypted)
    # @option attributes [String, nil] :request_text Human-readable request summary
    # @option attributes [String, nil] :response_text Human-readable response summary
    # @option attributes [Integer, nil] :input_tokens Prompt token count
    # @option attributes [Integer, nil] :output_tokens Completion token count
    # @option attributes [Integer, nil] :latency_ms Request duration in milliseconds
    # @option attributes [Symbol, String] :status :success, :error, or :canceled (default: :success)
    # @option attributes [String, nil] :error_class Exception class name on failure
    # @option attributes [String, nil] :error_message Exception message on failure
    # @option attributes [Array<String>] :tags Labels for filtering (e.g., ["prod", "urgent"])
    # @option attributes [Hash] :metadata Custom metadata (e.g., { ticket_id: 123 })
    # @option attributes [ActiveRecord::Base, nil] :user Associated user (polymorphic)
    # @option attributes [String, nil] :session_id Session identifier for grouping related calls
    # @option attributes [Integer, nil] :parent_id Parent interaction ID for hierarchical chains
    # @option attributes [String, nil] :idempotency_key Key for deduplication
    #
    # @return [Tracebook::Result] Result object with success/error information
    #
    # @example Recording a successful completion
    #   result = TraceBook.record!(
    #     provider: "openai",
    #     model: "gpt-4o-mini",
    #     request_payload: { messages: [{ role: "user", content: "Hello" }] },
    #     response_payload: { choices: [{ message: { content: "Hi!" } }] },
    #     input_tokens: 10,
    #     output_tokens: 5,
    #     latency_ms: 150,
    #     status: :success,
    #     trackable: current_user,
    #     tags: ["greeting"]
    #   )
    #
    # @example Recording a failed request
    #   TraceBook.record!(
    #     provider: "anthropic",
    #     model: "claude-3-5-sonnet",
    #     request_payload: request,
    #     response_payload: nil,
    #     status: :error,
    #     error_class: "Faraday::TimeoutError",
    #     error_message: "Request timed out after 30s",
    #     latency_ms: 30000
    #   )
    def record!(**attributes)
      payload = build_normalized_interaction(attributes)
      result = Result.new(idempotency_key: attributes[:idempotency_key])

      if config.persist_async
        PersistInteractionJob.perform_later(payload.to_h)
        result
      else
        interaction = PersistInteractionJob.perform_now(payload.to_h)
        Result.new(interaction: interaction, idempotency_key: attributes[:idempotency_key])
      end
    rescue StandardError => error
      Result.new(error: error, idempotency_key: attributes[:idempotency_key])
    end

    private

    def finalize_configuration!
      config.finalize!
      @configuration_finalized = true
    end

    def ensure_configurable!
      return unless @configuration_finalized || config.finalized?

      raise ConfigurationError, "TraceBook configuration is already finalized"
    end

    def build_normalized_interaction(attributes)
      NormalizedInteraction.new(
        provider: attributes.fetch(:provider),
        model: attributes.fetch(:model),
        project: attributes[:project],
        request_payload: attributes[:request_payload],
        response_payload: attributes[:response_payload],
        request_text: attributes[:request_text],
        response_text: attributes[:response_text],
        input_tokens: attributes[:input_tokens],
        output_tokens: attributes[:output_tokens],
        latency_ms: attributes[:latency_ms],
        status: attributes.fetch(:status, "success"),
        error_class: attributes[:error_class],
        error_message: attributes[:error_message],
        tags: Array(attributes[:tags]).compact,
        metadata: attributes[:metadata] || {},
        trackable: attributes[:trackable],
        parent_id: attributes[:parent_id],
        session_id: attributes[:session_id]
      )
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
