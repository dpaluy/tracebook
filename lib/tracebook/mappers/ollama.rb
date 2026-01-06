# frozen_string_literal: true

require_relative "base"

module Tracebook
  module Mappers
    class Ollama < Base
      def normalize(raw_request:, raw_response:, meta: {})
        request = symbolize(raw_request || {})
        response = symbolize(raw_response || {})
        meta_info = indifferent_meta(meta)

        metadata = {}
        metadata["eval_count"] = response[:eval_count] if response.key?(:eval_count)

        build_interaction(
          provider: "ollama",
          model: request[:model] || response[:model],
          project: meta_info[:project],
          request_payload: raw_request,
          response_payload: raw_response,
          request_text: request[:prompt] || request[:input],
          response_text: response[:response],
          input_tokens: meta_info[:input_tokens]&.to_i || response[:prompt_eval_count],
          output_tokens: meta_info[:output_tokens]&.to_i || response[:eval_count],
          latency_ms: meta_info[:latency_ms] || to_milliseconds(response[:total_duration]),
          status: meta_info[:status]&.to_sym || :success,
          error_class: nil,
          error_message: nil,
          tags: Array(meta_info[:tags]).compact,
          metadata: metadata,
          actor: meta_info[:actor],
          parent_id: meta_info[:parent_id],
          session_id: meta_info[:session_id]
        )
      end

      private

      def to_milliseconds(value)
        return unless value

        (value.to_f * 1000).to_i
      end
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
