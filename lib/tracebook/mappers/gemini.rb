# frozen_string_literal: true

require_relative "base"

module Tracebook
  module Mappers
    # Mapper for Google Gemini API responses.
    #
    # Gemini responses include usage metadata at the top level:
    #   {
    #     "content": "...",
    #     "usageMetadata": {
    #       "promptTokenCount": 50,
    #       "candidatesTokenCount": 25
    #     }
    #   }
    class Gemini < Base
      def normalize(raw_request:, raw_response:, meta: {})
        request = symbolize(raw_request || {})
        response = symbolize(raw_response || {})
        meta_info = indifferent_meta(meta)

        build_interaction(
          provider: "gemini",
          model: request[:model] || response[:model],
          project: meta_info[:project],
          request_payload: raw_request,
          response_payload: raw_response,
          request_text: extract_request_text(request),
          response_text: extract_response_text(response),
          input_tokens: gemini_token_count(meta_info, response, :input_tokens, :prompt_token_count),
          output_tokens: gemini_token_count(meta_info, response, :output_tokens, :candidates_token_count),
          latency_ms: meta_info[:latency_ms],
          status: meta_info[:status]&.to_sym || :success,
          error_class: nil,
          error_message: nil,
          tags: Array(meta_info[:tags]).compact,
          metadata: {},
          actor: meta_info[:actor],
          parent_id: meta_info[:parent_id],
          session_id: meta_info[:session_id]
        )
      end

      private

      def extract_request_text(request)
        # Extract text from Gemini request format
        # Can be either messages array or system_prompt + messages
        messages = request[:messages] || []
        Array(messages).map { |msg| msg.with_indifferent_access[:content].to_s }.reject(&:empty?).join("\n\n")
      end

      def extract_response_text(response)
        # Gemini response can be just a string or have a content field
        return response[:content].to_s if response[:content].is_a?(String)

        # If content is a hash/array, extract text
        content = response[:content]
        case content
        when Hash
          content.with_indifferent_access[:text].to_s
        when Array
          content.map do |part|
            part = part.with_indifferent_access
            part[:text].to_s
          end.join("\n\n")
        else
          content.to_s
        end
      end

      # Extract token count from meta (explicit, highest priority), response top-level
      # (RubyLLM format), or Gemini response usageMetadata (raw API format)
      def gemini_token_count(meta_info, response, meta_key, gemini_response_key)
        # First check if explicitly passed in meta (highest priority)
        return meta_info[meta_key]&.to_i if meta_info[meta_key].present?

        # Check top-level response (RubyLLM Message#to_h format)
        return response[meta_key]&.to_i if response[meta_key].present?

        # Extract from usageMetadata (raw Gemini API response format)
        usage = response[:usage_metadata] || response[:usageMetadata] || {}
        usage = usage.with_indifferent_access

        # Try both snake_case and camelCase variations
        case gemini_response_key
        when :prompt_token_count
          usage[:prompt_token_count]&.to_i || usage[:promptTokenCount]&.to_i
        when :candidates_token_count
          usage[:candidates_token_count]&.to_i || usage[:candidatesTokenCount]&.to_i
        else
          nil
        end
      end
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
