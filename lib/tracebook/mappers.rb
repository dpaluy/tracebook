# frozen_string_literal: true

require "active_support/core_ext/hash/indifferent_access"
require "active_support/core_ext/object/deep_dup"
require_relative "mappers/base"
require_relative "mappers/openai"
require_relative "mappers/anthropic"
require_relative "mappers/ollama"

module Tracebook
  # Mappers normalize provider-specific request/response formats into TraceBook's
  # standard {NormalizedInteraction} structure.
  #
  # Built-in mappers exist for OpenAI, Anthropic, and Ollama. For other providers,
  # a fallback mapper is used which preserves the raw payloads.
  #
  # @example Using the mapper in an adapter
  #   normalized = Tracebook::Mappers.normalize(
  #     "openai",
  #     raw_request: { model: "gpt-4o", messages: messages },
  #     raw_response: openai_response,
  #     meta: { project: "chatbot", user: current_user, latency_ms: 200 }
  #   )
  #   TraceBook.record!(**normalized.to_h)
  #
  # @example Creating a custom mapper
  #   # See {Mappers::Base} for the base class
  #   class Mappers::Cohere < Mappers::Base
  #     def self.normalize(raw_request:, raw_response:, meta: {})
  #       # Your normalization logic
  #       build_interaction(provider: "cohere", model: ..., ...)
  #     end
  #   end
  #
  # @see Mappers::Base
  # @see NormalizedInteraction
  module Mappers
    extend self

    # Normalizes a provider's request/response into standard format.
    #
    # Routes to provider-specific mappers for OpenAI, Anthropic, and Ollama.
    # Falls back to a generic mapper for unknown providers.
    #
    # @param provider [String] Provider name ("openai", "anthropic", "ollama", etc.)
    # @param raw_request [Hash] The original request sent to the provider
    # @param raw_response [Hash] The original response from the provider
    # @param meta [Hash] Additional metadata (project, user, session_id, tags, etc.)
    #
    # @option meta [String] :project Project name for filtering
    # @option meta [ActiveRecord::Base] :user Associated user
    # @option meta [String] :session_id Session identifier
    # @option meta [Integer] :parent_id Parent interaction ID
    # @option meta [Array<String>] :tags Labels for filtering
    # @option meta [Integer] :latency_ms Request duration in milliseconds
    # @option meta [Symbol] :status :success, :error, or :canceled
    # @option meta [String] :error_class Exception class name (for errors)
    # @option meta [String] :error_message Exception message (for errors)
    #
    # @return [NormalizedInteraction] Normalized interaction ready for {TraceBook.record!}
    #
    # @example Normalizing an OpenAI response
    #   normalized = Tracebook::Mappers.normalize(
    #     "openai",
    #     raw_request: {
    #       model: "gpt-4o",
    #       messages: [{ role: "user", content: "Hello" }]
    #     },
    #     raw_response: {
    #       choices: [{ message: { content: "Hi!" } }],
    #       usage: { prompt_tokens: 10, completion_tokens: 5 }
    #     },
    #     meta: { latency_ms: 150, user: current_user }
    #   )
    def normalize(provider, raw_request:, raw_response:, meta: {})
      case provider.to_s
      when "openai"
        normalize_openai(raw_request, raw_response, meta)
      when "anthropic"
        normalize_anthropic(raw_request, raw_response, meta)
      when "ollama"
        normalize_ollama(raw_request, raw_response, meta)
      else
        fallback_normalized(provider, raw_request, raw_response, meta)
      end
    end

    private

    def normalize_openai(raw_request, raw_response, meta)
      request = symbolize(raw_request || {})
      response = symbolize(raw_response || {})
      metadata = openai_metadata(response)
      meta_info = indifferent_meta(meta)

      Tracebook::NormalizedInteraction.new(
        provider: "openai",
        model: request[:model] || response[:model],
        project: meta_info[:project],
        request_payload: raw_request,
        response_payload: raw_response,
        request_text: join_messages(request[:messages]),
        response_text: openai_response_text(response),
        input_tokens: openai_usage_tokens(response, :prompt_tokens),
        output_tokens: openai_usage_tokens(response, :completion_tokens),
        latency_ms: meta_info[:latency_ms],
        status: meta_info[:status]&.to_sym || openai_status(response),
        error_class: nil,
        error_message: nil,
        tags: Array(meta_info[:tags]).compact,
        metadata: metadata,
        user: meta_info[:user],
        parent_id: meta_info[:parent_id],
        session_id: meta_info[:session_id]
      )
    end

    def normalize_anthropic(raw_request, raw_response, meta)
      request = symbolize(raw_request || {})
      response = symbolize(raw_response || {})
      meta_info = indifferent_meta(meta)

      Tracebook::NormalizedInteraction.new(
        provider: "anthropic",
        model: request[:model] || response[:model],
        project: meta_info[:project],
        request_payload: raw_request,
        response_payload: raw_response,
        request_text: extract_anthropic_messages(request[:messages]),
        response_text: extract_blocks(response[:content]).join("\n\n"),
        input_tokens: anthropic_usage(response, :input_tokens),
        output_tokens: anthropic_usage(response, :output_tokens),
        latency_ms: meta_info[:latency_ms],
        status: meta_info[:status]&.to_sym || :success,
        error_class: nil,
        error_message: nil,
        tags: Array(meta_info[:tags]).compact,
        metadata: {},
        user: meta_info[:user],
        parent_id: meta_info[:parent_id],
        session_id: meta_info[:session_id]
      )
    end

    def normalize_ollama(raw_request, raw_response, meta)
      request = symbolize(raw_request || {})
      response = symbolize(raw_response || {})
      meta_info = indifferent_meta(meta)

      metadata = {}
      metadata["eval_count"] = response[:eval_count] if response.key?(:eval_count)

      Tracebook::NormalizedInteraction.new(
        provider: "ollama",
        model: request[:model] || response[:model],
        project: meta_info[:project],
        request_payload: raw_request,
        response_payload: raw_response,
        request_text: request[:prompt] || request[:input],
        response_text: response[:response],
        input_tokens: response[:prompt_eval_count],
        output_tokens: response[:eval_count],
        latency_ms: meta_info[:latency_ms] || to_milliseconds(response[:total_duration]),
        status: meta_info[:status]&.to_sym || :success,
        error_class: nil,
        error_message: nil,
        tags: Array(meta_info[:tags]).compact,
        metadata: metadata,
        user: meta_info[:user],
        parent_id: meta_info[:parent_id],
        session_id: meta_info[:session_id]
      )
    end

    def fallback_normalized(provider, raw_request, raw_response, meta)
      request = symbolize(raw_request || {})
      response = symbolize(raw_response || {})
      meta_info = indifferent_meta(meta)

      Tracebook::NormalizedInteraction.new(
        provider: provider.to_s,
        model: request[:model] || response[:model],
        project: meta_info[:project],
        request_payload: raw_request,
        response_payload: raw_response,
        request_text: meta_info[:request_text],
        response_text: meta_info[:response_text],
        input_tokens: meta_info[:input_tokens],
        output_tokens: meta_info[:output_tokens],
        latency_ms: meta_info[:latency_ms],
        status: meta_info[:status]&.to_sym || :success,
        error_class: meta_info[:error_class],
        error_message: meta_info[:error_message],
        tags: Array(meta_info[:tags]).compact,
        metadata: meta_info[:metadata] || {},
        user: meta_info[:user],
        parent_id: meta_info[:parent_id],
        session_id: meta_info[:session_id]
      )
    end

    # OpenAI helpers
    def join_messages(messages)
      Array(messages).map { |message| message.with_indifferent_access[:content].to_s }.reject(&:empty?).join("\n\n")
    end

    def openai_first_choice(response)
      choices = Array(response[:choices])
      choices.first&.with_indifferent_access || {}
    end

    def openai_response_text(response)
      choice = openai_first_choice(response)
      message = choice[:message] || {}
      message.with_indifferent_access[:content].to_s
    end

    def openai_usage_tokens(response, key)
      usage = response[:usage] || {}
      usage.with_indifferent_access[key]&.to_i
    end

    def openai_metadata(response)
      choice = openai_first_choice(response)
      metadata = {}
      metadata["finish_reason"] = choice[:finish_reason] if choice[:finish_reason]
      metadata
    end

    def openai_status(response)
      finish_reason = openai_first_choice(response)[:finish_reason]
      return :canceled if finish_reason == "length"
      return :error if finish_reason == "error"

      :success
    end

    # Anthropic helpers
    def extract_anthropic_messages(messages)
      Array(messages).flat_map do |message|
        message = message.respond_to?(:with_indifferent_access) ? message.with_indifferent_access : message
        extract_blocks(message[:content])
      end.join("\n\n")
    end

    def extract_blocks(blocks)
      Array(blocks).flat_map do |block|
        block = block.respond_to?(:with_indifferent_access) ? block.with_indifferent_access : block
        case block[:type]
        when "text"
          block[:text]
        when "input_text"
          block[:text]
        else
          nil
        end
      end.compact
    end

    def anthropic_usage(response, key)
      usage = response[:usage] || {}
      usage.with_indifferent_access[key]&.to_i
    end

    # Ollama helpers
    def to_milliseconds(value)
      return unless value

      (value.to_f * 1000).to_i
    end

    # Common helpers
    def indifferent_meta(meta)
      (meta || {}).with_indifferent_access
    end

    def symbolize(hash)
      hash.deep_dup.transform_keys { |key| key.respond_to?(:to_sym) ? key.to_sym : key }
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
