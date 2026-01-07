# frozen_string_literal: true

module Tracebook
  module Redactors
    # LLM-based redactor for sophisticated PII detection.
    #
    # Uses an LLM to identify and redact PII that pattern-based redactors might miss,
    # such as names, addresses, and context-sensitive information.
    #
    # SECURITY WARNING: When using external LLM providers (OpenAI, Anthropic),
    # the text being redacted is sent to their servers. For maximum privacy,
    # use a local Ollama instance. Never use external providers for highly
    # sensitive data without explicit user consent.
    #
    # @example Configuration with OpenAI
    #   TraceBook.configure do |config|
    #     config.llm_redactor = Tracebook::Redactors::LLMBased.new(
    #       provider: :openai,
    #       model: "gpt-4o-mini",
    #       mode: :sync,
    #       on_failure: :log_and_continue
    #     )
    #   end
    #
    # @example Configuration with local Ollama (privacy-preserving)
    #   TraceBook.configure do |config|
    #     config.llm_redactor = Tracebook::Redactors::LLMBased.new(
    #       provider: :ollama,
    #       model: "llama3.2",
    #       mode: :sync,
    #       timeout: 30
    #     )
    #   end
    class LLMBased
      GUARD_KEY = :tracebook_llm_redaction_guard

      DEFAULT_TIMEOUT = 30
      DEFAULT_MODE = :sync
      DEFAULT_ON_FAILURE = :log_and_continue

      VALID_PROVIDERS = %i[openai anthropic ollama].freeze
      VALID_MODES = %i[sync async].freeze
      VALID_ON_FAILURE = %i[raise log_and_continue retry_async].freeze

      DEFAULT_PROMPT = <<~PROMPT
        You are a PII redaction assistant. Your task is to identify and redact
        personally identifiable information (PII) from the given text.

        Replace PII with appropriate markers:
        - Names: [NAME]
        - Addresses: [ADDRESS]
        - Dates of birth: [DOB]
        - Account numbers: [ACCOUNT]
        - Any other PII: [PII]

        IMPORTANT:
        - Preserve existing redaction markers like [EMAIL], [PHONE], [CARD]
        - Do NOT redact these markers
        - Only output the redacted text, nothing else
        - If no PII is found, output the original text unchanged
      PROMPT

      attr_reader :provider, :model, :mode, :on_failure, :timeout, :prompt

      # Creates a new LLM-based redactor.
      #
      # @param provider [Symbol] LLM provider (:openai, :anthropic, :ollama)
      # @param model [String] Model identifier (e.g., "gpt-4o-mini", "claude-3-haiku")
      # @param mode [Symbol] Execution mode (:sync or :async)
      # @param on_failure [Symbol] Failure handling (:raise, :log_and_continue, :retry_async)
      # @param timeout [Integer] Request timeout in seconds
      # @param prompt [String, :default] Custom system prompt or :default
      def initialize(provider:, model:, mode: DEFAULT_MODE, on_failure: DEFAULT_ON_FAILURE, timeout: DEFAULT_TIMEOUT, prompt: :default)
        validate_provider!(provider)
        validate_mode!(mode)
        validate_on_failure!(on_failure)

        @provider = provider.to_sym
        @model = model
        @mode = mode.to_sym
        @on_failure = on_failure.to_sym
        @timeout = timeout
        @prompt = prompt
      end

      # Redacts PII from text using the configured LLM.
      #
      # Uses IsolatedExecutionState guard to prevent infinite recursion when
      # TraceBook.record! is called within the LLM client (which would trigger
      # another redaction cycle).
      #
      # @param text [String] Text to redact
      # @param audit [RedactionAudit, nil] Optional audit object to record actions
      # @param field_path [String, nil] Optional field path for audit context
      # @return [Array<String, RedactionAudit>] Tuple of [redacted_text, audit]
      def call(text, audit: RedactionAudit.new, field_path: nil)
        return [ text, audit ] if guarded?
        return [ text, audit ] unless text.is_a?(String)
        return [ text, audit ] if text.length < 10 # Skip very short strings

        with_guard do
          perform_redaction(text, audit, field_path)
        end
      rescue StandardError => error
        handle_failure(error, text, audit, field_path)
      end

      # @return [Boolean] true if mode is :sync
      def sync?
        mode == :sync
      end

      # @return [Boolean] true if mode is :async
      def async?
        mode == :async
      end

      private

      def validate_provider!(provider)
        return if VALID_PROVIDERS.include?(provider.to_sym)

        raise ArgumentError, "Unknown provider: #{provider}. Valid: #{VALID_PROVIDERS.join(', ')}"
      end

      def validate_mode!(mode)
        return if VALID_MODES.include?(mode.to_sym)

        raise ArgumentError, "Unknown mode: #{mode}. Valid: #{VALID_MODES.join(', ')}"
      end

      def validate_on_failure!(on_failure)
        return if VALID_ON_FAILURE.include?(on_failure.to_sym)

        raise ArgumentError, "Unknown on_failure: #{on_failure}. Valid: #{VALID_ON_FAILURE.join(', ')}"
      end

      def guarded?
        ActiveSupport::IsolatedExecutionState[GUARD_KEY] == true
      end

      def with_guard
        ActiveSupport::IsolatedExecutionState[GUARD_KEY] = true
        yield
      ensure
        ActiveSupport::IsolatedExecutionState[GUARD_KEY] = false
      end

      def perform_redaction(text, audit, field_path)
        response = llm_request(text)
        redacted = extract_response_text(response)

        # Only record if text actually changed
        if redacted.present? && redacted != text
          updated_audit = audit.record_redaction("llm_based", field_path || "inline")
          [ redacted, updated_audit ]
        else
          [ text, audit ]
        end
      end

      def llm_request(text)
        client.chat(
          model: model,
          messages: build_messages(text),
          timeout: timeout
        )
      end

      def build_messages(text)
        [
          { role: "system", content: system_prompt },
          { role: "user", content: text }
        ]
      end

      def system_prompt
        prompt == :default ? DEFAULT_PROMPT.strip : prompt
      end

      def client
        @client ||= build_client
      end

      def build_client
        case provider
        when :openai
          require_openai
          OpenAI::Client.new
        when :anthropic
          require_anthropic
          Anthropic::Client.new
        when :ollama
          require_ollama
          Ollama.new(url: ollama_url)
        end
      end

      def require_openai
        require "openai"
      rescue LoadError
        raise LoadError, "The 'ruby-openai' gem is required for OpenAI provider. Add `gem 'ruby-openai'` to your Gemfile."
      end

      def require_anthropic
        require "anthropic"
      rescue LoadError
        raise LoadError, "The 'anthropic' gem is required for Anthropic provider. Add `gem 'anthropic'` to your Gemfile."
      end

      def require_ollama
        require "ollama-ai"
      rescue LoadError
        raise LoadError, "The 'ollama-ai' gem is required for Ollama provider. Add `gem 'ollama-ai'` to your Gemfile."
      end

      def ollama_url
        ENV.fetch("OLLAMA_URL", "http://localhost:11434")
      end

      def extract_response_text(response)
        case provider
        when :openai
          response.dig("choices", 0, "message", "content")
        when :anthropic
          response.dig("content", 0, "text")
        when :ollama
          response.dig("message", "content")
        end || ""
      end

      def handle_failure(error, text, audit, field_path)
        updated_audit = audit.record_redaction("llm_based_failure:#{error.class.name}", field_path || "inline")

        case on_failure
        when :raise
          raise
        when :retry_async
          # In sync mode, mark for async retry
          if sync?
            Rails.logger.warn("[TraceBook] LLM redaction failed, marked for async retry: #{error.message}")
          end
          [ text, updated_audit ]
        else # :log_and_continue
          Rails.logger.error("[TraceBook] LLM redaction failed: #{error.message}")
          [ text, updated_audit ]
        end
      end
    end
  end
end
