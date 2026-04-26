# frozen_string_literal: true

module Tracebook
  class Config
    class OpenAiPrivacyFilterConfig
      attr_accessor :enabled, :endpoint, :timeout, :failure_mode
      attr_reader :label_map

      def initialize
        @enabled = false
        @endpoint = Redaction::OpenAiPrivacyFilter::DEFAULT_ENDPOINT
        @timeout = Redaction::OpenAiPrivacyFilter::DEFAULT_TIMEOUT
        @failure_mode = Redaction::OpenAiPrivacyFilter::DEFAULT_FAILURE_MODE
        @label_map = Redaction::OpenAiPrivacyFilter::DEFAULT_LABEL_MAP.dup
      end

      def enabled?
        enabled == true
      end

      def label_map=(label_map)
        @label_map = normalize_label_map(label_map)
      end

      def finalize!
        validate! if enabled?
        label_map.freeze
        freeze
      end

      private

      def validate!
        Redaction::OpenAiPrivacyFilter::Client.validate_endpoint!(endpoint)
        Redaction::OpenAiPrivacyFilter.validate_failure_mode!(failure_mode)
      end

      def normalize_label_map(label_map)
        label_map.to_h.transform_keys(&:to_s).transform_values(&:to_s)
      end
    end

    # @return [String] class name of the host app's Chat model (default: "Chat")
    attr_accessor :chat_class

    # @return [String] class name of the host app's Message model (default: "Message")
    attr_accessor :message_class

    # @return [String] currency code for cost calculations (default: "USD")
    attr_accessor :default_currency

    # @return [Integer] items per page in dashboard (default: 25)
    attr_accessor :per_page

    # @return [Proc, nil] lambda to format actor display name
    attr_accessor :actor_display

    # @return [Array<Proc>] custom redaction callables
    attr_reader :custom_redactors

    # @return [OpenAiPrivacyFilterConfig] model-backed redaction config
    attr_reader :openai_privacy_filter

    def initialize
      @chat_class = "Chat"
      @message_class = "Message"
      @default_currency = "USD"
      @per_page = 25
      @actor_display = nil
      @redaction_patterns = []
      @custom_redactors = []
      @openai_privacy_filter = OpenAiPrivacyFilterConfig.new
    end

    # Enable named redaction patterns.
    #
    # @example
    #   config.redact :email, :phone, :ssn, :credit_card
    def redact(*names)
      names.each do |name|
        if Redaction::GROUPS.key?(name)
          redact_group(name)
        elsif Redaction::PATTERNS.key?(name)
          @redaction_patterns << name unless @redaction_patterns.include?(name)
        else
          raise ArgumentError, "Unknown redaction pattern: #{name}. Available: #{(Redaction::PATTERNS.keys + Redaction::GROUPS.keys).join(", ")}"
        end
      end
    end

    # Enable a named group of patterns.
    #
    # @example
    #   config.redact_group :api_keys
    def redact_group(group_name)
      patterns = Redaction::GROUPS.fetch(group_name) do
        raise ArgumentError, "Unknown redaction group: #{group_name}. Available: #{Redaction::GROUPS.keys.join(", ")}"
      end
      patterns.each { |name| redact(name) }
    end

    # Add a custom regex pattern for redaction.
    #
    # @example
    #   config.redact_pattern(/policy[:\s]*\d{10}/i, "[POLICY_NUMBER]", name: "policy_number")
    def redact_pattern(regex, replacement, name: nil)
      pattern = Redaction::Pattern.new(
        name: name || "custom_#{@redaction_patterns.size}",
        regex: regex,
        replacement: replacement
      )
      @redaction_patterns << pattern
    end

    # Build the redaction pipeline from configured patterns and custom redactors.
    # Memoized after first call (safe because config is frozen after finalize!).
    #
    # @return [Redaction::Pipeline]
    def redaction_pipeline
      @redaction_pipeline || build_redaction_pipeline
    end

    def finalized?
      @finalized == true
    end

    def finalize!
      return if finalized?

      @redaction_patterns.freeze
      @custom_redactors.freeze
      @openai_privacy_filter.finalize!
      @redaction_pipeline = redaction_pipeline
      @finalized = true
      freeze
    end

    # @return [Class] the resolved chat model class
    def chat_model
      @chat_class.constantize
    end

    # @return [Class] the resolved message model class
    def message_model
      @message_class.constantize
    end

    private

    def build_redaction_pipeline
      patterns = @redaction_patterns.map do |p|
        p.is_a?(Symbol) ? Redaction::PATTERNS.fetch(p) : p
      end
      Redaction::Pipeline.new(
        patterns: patterns,
        custom_redactors: configured_redactors
      )
    end

    def configured_redactors
      redactors = @custom_redactors.dup
      redactors << openai_privacy_filter_redactor if openai_privacy_filter.enabled?
      redactors
    end

    def openai_privacy_filter_redactor
      Redaction::OpenAiPrivacyFilter.new(
        endpoint: openai_privacy_filter.endpoint,
        timeout: openai_privacy_filter.timeout,
        failure_mode: openai_privacy_filter.failure_mode,
        label_map: openai_privacy_filter.label_map
      )
    end
  end
end
