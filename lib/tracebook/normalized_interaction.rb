# frozen_string_literal: true

module Tracebook
  # Normalized representation of an LLM interaction.
  #
  # This immutable data structure provides a standard format for LLM interactions
  # across different providers. Mappers convert provider-specific formats into this
  # structure before persistence.
  #
  # @attr provider [String] Provider name (e.g., "openai", "anthropic")
  # @attr model [String] Model identifier (e.g., "gpt-4o", "claude-3-5-sonnet")
  # @attr project [String, nil] Project name for filtering
  # @attr request_payload [Hash] Full request sent to provider (will be encrypted)
  # @attr response_payload [Hash] Full response from provider (will be encrypted)
  # @attr request_text [String, nil] Human-readable request summary
  # @attr response_text [String, nil] Human-readable response summary
  # @attr input_tokens [Integer, nil] Prompt token count
  # @attr output_tokens [Integer, nil] Completion token count
  # @attr latency_ms [Integer, nil] Request duration in milliseconds
  # @attr status [Symbol, String] :success, :error, or :canceled
  # @attr error_class [String, nil] Exception class name on failure
  # @attr error_message [String, nil] Exception message on failure
  # @attr tags [Array<String>] Labels for filtering
  # @attr metadata [Hash] Custom metadata
  # @attr actor [ActiveRecord::Base, nil] Entity who triggers LLM request (polymorphic)
  # @attr parent_id [Integer, nil] Parent interaction ID for hierarchical chains
  # @attr session_id [String, nil] Session identifier for grouping related calls
  #
  # @example Creating a normalized interaction
  #   interaction = NormalizedInteraction.new(
  #     provider: "openai",
  #     model: "gpt-4o",
  #     request_payload: { messages: messages },
  #     response_payload: response,
  #     input_tokens: 100,
  #     output_tokens: 50,
  #     status: :success
  #   )
  #
  # @see Mappers
  NormalizedInteraction = Data.define(
    :provider,
    :model,
    :project,
    :request_payload,
    :response_payload,
    :request_text,
    :response_text,
    :input_tokens,
    :output_tokens,
    :latency_ms,
    :status,
    :error_class,
    :error_message,
    :tags,
    :metadata,
    :actor,
    :parent_id,
    :session_id
  ) do
    def initialize(
      provider:,
      model:,
      project: nil,
      request_payload: {},
      response_payload: {},
      request_text: nil,
      response_text: nil,
      input_tokens: nil,
      output_tokens: nil,
      latency_ms: nil,
      status: "success",
      error_class: nil,
      error_message: nil,
      tags: [],
      metadata: {},
      actor: nil,
      parent_id: nil,
      session_id: nil
    )
      super
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
