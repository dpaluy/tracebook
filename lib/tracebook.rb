require "pagy"
require "tracebook/version"
require "tracebook/engine"
require "tracebook/errors"
require "tracebook/redaction/pattern"
require "tracebook/redaction/pipeline"
require "tracebook/redaction/openai_privacy_filter"
require "tracebook/config"
require "tracebook/pricing"
require "tracebook/adapters"
require "tracebook/seeds/pricing_rules"

# TraceBook is a Rails engine for cost tracking and review of LLM conversations.
#
# It works as a layer on top of RubyLLM, adding:
# - Cost calculation per message based on pricing rules
# - Review workflow (approve/flag) per chat
# - Dashboard UI for monitoring LLM usage
#
# @example Configuration
#   Tracebook.configure do |config|
#     config.chat_class = "Chat"
#     config.message_class = "Message"
#     config.default_currency = "USD"
#     config.actor_display = ->(actor) { actor.try(:name) }
#   end
#
# @example Cost calculation
#   Tracebook.calculate_cost!(message)
module Tracebook
  class << self
    def config
      @config ||= Config.new
    end

    def configure
      ensure_configurable!
      yield(config)
      finalize_configuration!
      config
    end

    def reset_configuration!
      @config = Config.new
      @configuration_finalized = false
    end

    # Redact PII from text using configured patterns and custom redactors.
    #
    # @param text [String] the text to redact
    # @return [String] redacted text
    def redact(text)
      config.redaction_pipeline.call(text)
    end

    # Calculate and store cost for a message.
    #
    # @param message [ActiveRecord::Base] a message record with input_tokens, output_tokens
    # @param provider [String] provider name (e.g., "openai", "anthropic")
    # @param model [String] model identifier (e.g., "gpt-4o")
    # @param latency_ms [Integer, nil] request duration in milliseconds
    # @return [Tracebook::MessageCost] the created cost record
    def calculate_cost!(message, provider:, model:, latency_ms: nil)
      cost = Pricing::Calculator.call(
        provider: provider,
        model: model,
        input_tokens: message.input_tokens,
        output_tokens: message.output_tokens,
        occurred_at: message.created_at
      )

      MessageCost.create!(
        message: message,
        cost_input_cents: cost.input_cents,
        cost_output_cents: cost.output_cents,
        cost_total_cents: cost.total_cents,
        currency: cost.currency || config.default_currency,
        latency_ms: latency_ms
      )
    end

    private

    def finalize_configuration!
      config.finalize!
      @configuration_finalized = true
    end

    def ensure_configurable!
      return unless @configuration_finalized || config.finalized?

      raise ConfigurationError, "Tracebook configuration is already finalized"
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
