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
require "tracebook/redaction_audit"
require "tracebook/pricing"
require "tracebook/adapters"
require "tracebook/seeds/pricing_rules"

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
#     actor: current_user,
#     session_id: @conversation.id.to_s,
#     metadata: { context_label: "Form ##{@form.id} filling" },
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

    # Serializes an actor for job-safe persistence.
    #
    # Converts an ActiveRecord object (or similar) into a hash that can be
    # safely passed to background jobs. Prefers GlobalID when available for
    # reliable deserialization, falls back to type/id tuple otherwise.
    #
    # @param actor [ActiveRecord::Base, nil] The actor to serialize
    # @return [Hash] Serialized actor data with :actor_gid or :actor_type/:actor_id keys
    #
    # @example With a User model (GlobalID available)
    #   TraceBook.serialize_actor(User.find(1))
    #   # => { actor_gid: "gid://myapp/User/1" }
    #
    # @example With a plain object (no GlobalID)
    #   TraceBook.serialize_actor(some_object)
    #   # => { actor_type: "SomeObject", actor_id: 123 }
    #
    # @example With nil
    #   TraceBook.serialize_actor(nil)
    #   # => {}
    def serialize_actor(actor)
      return {} unless actor

      if actor.respond_to?(:to_global_id)
        { actor_gid: actor.to_global_id.to_s }
      elsif actor.respond_to?(:id) && actor.class.respond_to?(:name)
        { actor_type: actor.class.name, actor_id: actor.id }
      else
        {}
      end
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
    # @option attributes [Hash] :metadata Custom metadata (e.g., { context_label: "Form filling" })
    # @option attributes [ActiveRecord::Base, nil] :actor Entity who triggers LLM request (polymorphic)
    # @option attributes [String, nil] :session_id Session identifier for grouping related calls (auto-generated if missing)
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
    #     actor: current_user,
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
      # Build normalized interaction and apply redaction BEFORE job enqueue
      # This ensures no raw PII ever enters the job queue (critical security fix)
      payload = build_normalized_interaction(attributes)
      redacted_payload = apply_redaction(payload)

      result = Result.new(idempotency_key: attributes[:idempotency_key])

      if config.persist_async
        PersistInteractionJob.perform_later(redacted_payload.to_h)
        result
      else
        interaction = PersistInteractionJob.perform_now(redacted_payload.to_h)
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

    def apply_redaction(normalized)
      # Serialize actor BEFORE pipeline (deep_dup doesn't handle arbitrary objects well)
      actor_data = serialize_actor(normalized.actor)

      pipeline = RedactionPipeline.new(config: config)
      redacted = pipeline.call(normalized)

      # Return new normalized with serialized actor data
      # Remove :actor (raw object) and :redaction_audit (not serializable by ActiveJob)
      # redaction_audit is for call-time observability, not persistence
      NormalizedInteraction.new(
        **redacted.to_h.except(:actor, :redaction_audit).merge(actor_data)
      )
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
        actor: attributes[:actor],
        parent_id: attributes[:parent_id],
        session_id: attributes[:session_id]
      )
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
