# frozen_string_literal: true

module Tracebook
  # Background job for async LLM-based PII redaction.
  #
  # This job processes interactions that need additional LLM-based redaction
  # after initial pattern-based redaction. Useful for catching PII that
  # patterns miss (names, addresses, context-sensitive data).
  #
  # Uses pessimistic locking to prevent race conditions and supports
  # exponential backoff retry on failures.
  #
  # @example Enqueue for async processing
  #   LlmRedactionJob.perform_later(interaction.id)
  #
  # @example From retry_async failure mode
  #   # When LLMBased redactor fails with on_failure: :retry_async,
  #   # this job can be enqueued to retry later
  #   LlmRedactionJob.perform_later(interaction.id)
  class LlmRedactionJob < ApplicationJob
    queue_as :tracebook_llm_redaction

    # Retry configuration
    RETRY_CONFIG = {
      max_attempts: 3,
      base_delay: 30.seconds,
      max_delay: 5.minutes
    }.freeze

    # Retry on standard errors with exponential backoff
    retry_on StandardError,
      wait: :polynomially_longer,
      attempts: RETRY_CONFIG[:max_attempts]

    # Don't retry if interaction was deleted
    discard_on ActiveRecord::RecordNotFound

    # @param interaction_id [Integer] ID of interaction to process
    def perform(interaction_id)
      interaction = Interaction.lock.find(interaction_id)

      # Skip if already processed successfully
      return if llm_redaction_complete?(interaction)

      redactor = Tracebook.config.llm_redactor
      return mark_skipped(interaction, "no_llm_redactor_configured") unless redactor

      process_redaction(interaction, redactor)
    rescue StandardError => error
      record_failure(interaction, error) if interaction
      raise # Let ActiveJob handle retry
    end

    private

    def llm_redaction_complete?(interaction)
      status = interaction.metadata&.dig("llm_redaction_status")
      status == "success"
    end

    def process_redaction(interaction, redactor)
      # Redact request payload
      if interaction.request_payload.present?
        request_json = JSON.generate(interaction.request_payload)
        redacted_request, = redactor.call(request_json, audit: RedactionAudit.new)
        interaction.request_payload = JSON.parse(redacted_request)
      end

      # Redact response payload
      if interaction.response_payload.present?
        response_json = JSON.generate(interaction.response_payload)
        redacted_response, = redactor.call(response_json, audit: RedactionAudit.new)
        interaction.response_payload = JSON.parse(redacted_response)
      end

      # Redact text fields
      if interaction.request_text.present?
        interaction.request_text, = redactor.call(interaction.request_text, audit: RedactionAudit.new)
      end

      if interaction.response_text.present?
        interaction.response_text, = redactor.call(interaction.response_text, audit: RedactionAudit.new)
      end

      # Update metadata with success status
      update_metadata(interaction, {
        "llm_redaction_status" => "success",
        "llm_redacted_at" => Time.current.iso8601
      })

      interaction.save!
    end

    def mark_skipped(interaction, reason)
      update_metadata(interaction, {
        "llm_redaction_status" => "skipped",
        "llm_redaction_reason" => reason
      })
      interaction.save!
    end

    def record_failure(interaction, error)
      current_attempts = interaction.metadata&.dig("llm_redaction_attempts").to_i

      update_metadata(interaction, {
        "llm_redaction_status" => "failed",
        "llm_redaction_error" => error.message,
        "llm_redaction_attempts" => current_attempts + 1,
        "llm_redaction_last_attempt" => Time.current.iso8601
      })
      interaction.save!
    rescue StandardError => save_error
      # Log but don't raise - the original error should propagate
      Rails.logger.error("[TraceBook] Failed to record LLM redaction failure: #{save_error.message}")
    end

    def update_metadata(interaction, updates)
      interaction.metadata = (interaction.metadata || {}).merge(updates)
    end
  end
end
