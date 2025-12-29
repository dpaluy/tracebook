# frozen_string_literal: true

require "json"
require "stringio"
require "securerandom"
require "time"

module Tracebook
  # Background job for persisting LLM interactions.
  #
  # Handles the complete persistence pipeline:
  # 1. Deserialize payload
  # 2. Apply PII redaction
  # 3. Calculate cost based on pricing rules
  # 4. Store interaction in database (with encryption)
  # 5. Handle large payloads via ActiveStorage
  # 6. Enqueue rollup job for analytics
  #
  # This job is enqueued by {Tracebook.record!} when `config.persist_async` is true.
  #
  # @example Enqueuing directly
  #   PersistInteractionJob.perform_later(
  #     provider: "openai",
  #     model: "gpt-4o",
  #     request_payload: { messages: messages },
  #     response_payload: response,
  #     input_tokens: 100,
  #     output_tokens: 50
  #   )
  #
  # @example Synchronous execution (testing)
  #   interaction = PersistInteractionJob.perform_now(payload)
  #
  # @see Tracebook.record!
  # @see RedactionPipeline
  # @see Pricing::Calculator
  class PersistInteractionJob < ApplicationJob
    # Default inline payload size threshold (64KB)
    INLINE_THRESHOLD_BYTES = 64 * 1024

    # Processes and persists an LLM interaction.
    #
    # @param payload [Hash] Normalized interaction attributes
    # @return [Interaction] The persisted interaction record
    #
    # @raise [ActiveRecord::RecordInvalid] if interaction fails validation
    def perform(payload)
      normalized = from_payload(payload)
      redacted = redaction_pipeline.call(normalized)
      cost = Pricing::Calculator.call(
        provider: redacted.provider,
        model: redacted.model,
        input_tokens: redacted.input_tokens,
        output_tokens: redacted.output_tokens,
        occurred_at: occurred_at(redacted)
      )

      interaction = persist_interaction(redacted, cost)
      enqueue_rollup(interaction)
      interaction
    end

    private

    def from_payload(payload)
      attributes = payload.to_h.deep_symbolize_keys
      NormalizedInteraction.new(**attributes)
    end

    def persist_interaction(normalized, cost)
      attributes = {
        provider: normalized.provider,
        model: normalized.model,
        project: normalized.project,
        request_text: normalized.request_text,
        response_text: normalized.response_text,
        input_tokens: normalized.input_tokens,
        output_tokens: normalized.output_tokens,
        total_tokens: total_tokens(normalized),
        latency_ms: normalized.latency_ms,
        status: normalized.status,
        error_class: normalized.error_class,
        error_message: normalized.error_message,
        tags: normalized.tags,
        metadata: normalized.metadata,
        parent_id: normalized.parent_id,
        session_id: normalized.session_id,
        cost_input_cents: cost.input_cents,
        cost_output_cents: cost.output_cents,
        cost_total_cents: cost.total_cents,
        currency: cost.currency || Tracebook.config.default_currency
      }

      ActiveRecord::Base.transaction do
        Interaction.create!(attributes).tap do |interaction|
          interaction.trackable = normalized.trackable if normalized.trackable
          persist_payloads(interaction, normalized)
          interaction.save! if interaction.changed?
        end
      end
    end

    def total_tokens(normalized)
      [ normalized.input_tokens.to_i, normalized.output_tokens.to_i ].compact.sum
    end

    def persist_payloads(interaction, normalized)
      store_payload(:request, interaction, normalized.request_payload)
      store_payload(:response, interaction, normalized.response_payload)
    end

    def store_payload(type, interaction, payload)
      return if payload.nil?

      serialized = JSON.generate(payload)
      if serialized.bytesize > inline_threshold
        blob = create_blob(serialized, "#{type}-payload")
        interaction.public_send("#{type}_payload_store=", "active_storage")
        interaction.public_send("#{type}_payload_blob_id=", blob.id)
        interaction.public_send("#{type}_payload=", nil)
      else
        interaction.public_send("#{type}_payload_store=", "inline")
        interaction.public_send("#{type}_payload=", payload)
      end
    end

    def inline_threshold
      Tracebook.config.inline_payload_bytes
    end

    def create_blob(contents, label)
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(contents),
        filename: "tracebook-#{label}-#{SecureRandom.uuid}.json",
        content_type: "application/json"
      )
    end

    def enqueue_rollup(interaction)
      DailyRollupsJob.perform_later(
        date: interaction.created_at.to_date,
        provider: interaction.provider,
        model: interaction.model,
        project: interaction.project
      )
    end

    def redaction_pipeline
      @redaction_pipeline ||= RedactionPipeline.new(config: Tracebook.config)
    end

    def occurred_at(normalized)
      normalized.metadata && normalized.metadata["timestamp"] ? Time.parse(normalized.metadata["timestamp"].to_s) : Time.current
    rescue ArgumentError
      Time.current
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
