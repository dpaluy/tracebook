# frozen_string_literal: true

require_relative "base"

module Tracebook
  module Mappers
    class OpenAI < Base
      def normalize(raw_request:, raw_response:, meta: {})
        request = symbolize(raw_request || {})
        response = symbolize(raw_response || {})
        metadata = build_metadata(response)
        meta_info = indifferent_meta(meta)

        build_interaction(
          provider: "openai",
          model: request[:model] || response[:model],
          project: meta_info[:project],
          request_payload: raw_request,
          response_payload: raw_response,
          request_text: join_messages(request[:messages]),
          response_text: first_choice_text(response),
          input_tokens: token_count(meta_info, :input_tokens, response, :prompt_tokens),
          output_tokens: token_count(meta_info, :output_tokens, response, :completion_tokens),
          latency_ms: meta_info[:latency_ms],
          status: meta_info[:status]&.to_sym || default_status(response),
          error_class: nil,
          error_message: nil,
          tags: Array(meta_info[:tags]).compact,
          metadata: metadata,
          user: meta_info[:user],
          parent_id: meta_info[:parent_id],
          session_id: meta_info[:session_id]
        )
      end

      private

      def join_messages(messages)
        Array(messages).map { |message| message.with_indifferent_access[:content].to_s }.reject(&:empty?).join("\n\n")
      end

      def first_choice(response)
        Array(response[:choices]).first || {}
      end

      def first_choice_text(response)
        choice = first_choice(response)
        message = choice[:message] || {}
        message.with_indifferent_access[:content].to_s
      end

      def build_metadata(response)
        choice = first_choice(response)
        metadata = {}
        metadata["finish_reason"] = choice[:finish_reason] if choice[:finish_reason]
        metadata
      end

      def default_status(response)
        finish_reason = first_choice(response)[:finish_reason]
        return :canceled if finish_reason == "length"
        return :error if finish_reason == "error"

        :success
      end
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
