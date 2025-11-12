# frozen_string_literal: true

require_relative "base"

module Tracebook
  module Mappers
    class Anthropic < Base
      def normalize(raw_request:, raw_response:, meta: {})
        request = symbolize(raw_request || {})
        response = symbolize(raw_response || {})
        meta_info = indifferent_meta(meta)

        build_interaction(
          provider: "anthropic",
          model: request[:model] || response[:model],
          project: meta_info[:project],
          request_payload: raw_request,
          response_payload: raw_response,
          request_text: extract_blocks(request[:messages]),
          response_text: extract_blocks(response[:content]),
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

      private

      def extract_blocks(blocks)
        Array(blocks).flat_map do |block|
          block = block.with_indifferent_access
          case block[:type]
          when "text"
            block[:text]
          when "input_text"
            block[:text]
          else
            nil
          end
        end.compact.join("\n\n")
      end

      def anthropic_usage(response, key)
        usage = response[:usage] || {}
        usage.with_indifferent_access[key]&.to_i
      end
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
