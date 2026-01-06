# frozen_string_literal: true

require "active_support/notifications"
require "active_support/core_ext/hash/indifferent_access"

module Tracebook
  module Adapters
    # Adapter for capturing LLM interactions via ActiveSupport::Notifications.
    #
    # This adapter subscribes to instrumentation events (default: "ruby_llm.request")
    # and automatically records interactions in TraceBook.
    #
    # @example Basic setup
    #   # config/initializers/tracebook_adapters.rb
    #   TraceBook::Adapters::RubyLLM.enable!
    #
    # @example Custom event name
    #   TraceBook::Adapters::RubyLLM.enable!(instrumentation: "my_llm.complete")
    #
    # @example Emitting events from your LLM client
    #   ActiveSupport::Notifications.instrument("ruby_llm.request", {
    #     provider: "openai",
    #     request: { model: "gpt-4o", messages: messages },
    #     response: response,
    #     meta: {
    #       project: "support",
    #       actor: current_user,
    #       session_id: session.id,
    #       latency_ms: 150,
    #       status: :success,
    #       tags: ["production", "triage"]
    #     }
    #   })
    #
    # @see Mappers
    module RubyLLM
      extend self

      # Default ActiveSupport::Notifications event name
      DEFAULT_EVENT = "ruby_llm.request".freeze

      # Enables the adapter to start capturing events.
      #
      # Subscribes to the specified instrumentation event and routes payloads
      # through {Mappers} to {TraceBook.record!}.
      #
      # @param instrumentation [String] Event name to subscribe to
      # @return [void]
      #
      # @example
      #   TraceBook::Adapters::RubyLLM.enable!
      #   TraceBook::Adapters::RubyLLM.enable!(instrumentation: "custom.llm")
      def enable!(instrumentation: DEFAULT_EVENT)
        return if subscribers.key?(instrumentation)

        subscribers[instrumentation] = ActiveSupport::Notifications.subscribe(instrumentation) do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          handle_payload(event.payload.with_indifferent_access)
        end
      end

      # Disables the adapter and unsubscribes from events.
      #
      # @param instrumentation [String] Event name to unsubscribe from
      # @return [void]
      #
      # @example
      #   TraceBook::Adapters::RubyLLM.disable!
      def disable!(instrumentation: DEFAULT_EVENT)
        token = subscribers.delete(instrumentation)
        ActiveSupport::Notifications.unsubscribe(token) if token
      end

      private

      def handle_payload(payload)
        provider = payload[:provider].to_s.presence || "ruby_llm"
        normalized = Mappers.normalize(
          provider,
          raw_request: payload[:request],
          raw_response: payload[:response],
          meta: payload[:meta] || {}
        )

        TraceBook.record!(**normalized.to_h)
      rescue KeyError => error
        Rails.logger.error("TraceBook RubyLLM adapter error: #{error.message}") if defined?(Rails)
      end

      def subscribers
        @subscribers ||= {}
      end
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
