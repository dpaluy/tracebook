# frozen_string_literal: true

require "active_support/core_ext/hash/indifferent_access"
require "active_support/core_ext/object/deep_dup"

module Tracebook
  # Normalizes RubyLLM responses into TraceBook's standard NormalizedInteraction structure.
  #
  # RubyLLM abstracts all LLM providers (OpenAI, Anthropic, Gemini, etc.) into a consistent
  # Message format with top-level input_tokens/output_tokens fields.
  #
  # @example Using the mapper
  #   normalized = Tracebook::Mappers.normalize(
  #     "gemini",
  #     raw_request: { model: "gemini-2.0-flash", messages: messages },
  #     raw_response: response.to_h,
  #     meta: { project: "chatbot", actor: current_user, latency_ms: 200 }
  #   )
  #   TraceBook.record!(**normalized.to_h)
  module Mappers
    extend self

    # Normalizes a RubyLLM response into standard format.
    #
    # @param provider [String] Provider name ("openai", "anthropic", "gemini", etc.)
    # @param raw_request [Hash] The original request sent to the provider
    # @param raw_response [Hash] RubyLLM Message#to_h response
    # @param meta [Hash] Additional metadata
    #
    # @return [NormalizedInteraction] Normalized interaction ready for TraceBook.record!
    def normalize(provider, raw_request:, raw_response:, meta: {})
      request = symbolize(raw_request || {})
      response = symbolize(raw_response || {})
      meta_info = indifferent_meta(meta)

      Tracebook::NormalizedInteraction.new(
        provider: provider.to_s,
        model: response[:model_id],
        project: meta_info[:project],
        request_payload: raw_request,
        response_payload: raw_response,
        request_text: extract_request_text(request),
        response_text: response[:content].to_s,
        input_tokens: response[:input_tokens]&.to_i,
        output_tokens: response[:output_tokens]&.to_i,
        latency_ms: meta_info[:latency_ms],
        status: meta_info[:status]&.to_sym || :success,
        error_class: meta_info[:error_class],
        error_message: meta_info[:error_message],
        tags: Array(meta_info[:tags]).compact,
        metadata: {},
        actor: meta_info[:actor],
        parent_id: meta_info[:parent_id],
        session_id: meta_info[:session_id]
      )
    end

    private

    def extract_request_text(request)
      messages = request[:messages] || []
      Array(messages).map { |msg| msg.with_indifferent_access[:content].to_s }.reject(&:empty?).join("\n\n")
    end

    def indifferent_meta(meta)
      result = (meta || {}).with_indifferent_access
      result[:actor] ||= result[:trackable]
      result
    end

    def symbolize(hash)
      hash.deep_dup.transform_keys { |key| key.respond_to?(:to_sym) ? key.to_sym : key }
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
