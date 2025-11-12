# frozen_string_literal: true

require "active_support/core_ext/hash/indifferent_access"

module Tracebook
  module Adapters
    module ActiveAgent
      extend self

      def enable!(bus: nil)
        bus ||= discover_bus
        return unless bus.respond_to?(:subscribe)

        subscribers << bus.subscribe { |event| handle_event(event) }
      end

      def disable!
        subscribers.clear
      end

      private

      def handle_event(event)
        payload = event.with_indifferent_access
        provider = payload[:provider]&.to_s.presence || "active_agent"
        mapper = mapper_for(provider)
        meta_hash = payload[:meta] || {}
        meta = meta_hash.merge(
          session_id: payload[:session_id],
          parent_id: payload[:parent_id]
        )

        normalized = if mapper
                        mapper.normalize(raw_request: payload[:request], raw_response: payload[:response], meta: meta)
        else
                        fallback(provider, payload, meta)
        end

        TraceBook.record!(**normalized.to_h)
      end

      def mapper_for(provider)
        case provider
        when "openai"
          Tracebook::Mappers::OpenAI.new
        when "anthropic"
          Tracebook::Mappers::Anthropic.new
        when "ollama"
          Tracebook::Mappers::Ollama.new
        else
          nil
        end
      end

      def fallback(provider, payload, meta)
        NormalizedInteraction.new(
          provider: provider,
          model: payload.dig(:request, :model),
          project: meta[:project],
          request_payload: payload[:request],
          response_payload: payload[:response],
          status: meta[:status] || :success,
          tags: Array(meta[:tags]),
          session_id: meta[:session_id],
          parent_id: meta[:parent_id]
        )
      end

      def subscribers
        @subscribers ||= []
      end

      def discover_bus
        ActiveAgent::Bus if defined?(ActiveAgent::Bus)
      rescue NameError
        nil
      end
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
