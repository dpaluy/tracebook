# frozen_string_literal: true

module Tracebook
  class Config
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

    def initialize
      @chat_class = "Chat"
      @message_class = "Message"
      @default_currency = "USD"
      @per_page = 25
      @actor_display = nil
      @redaction_patterns = []
      @custom_redactors = []
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
      Redaction::Pipeline.new(patterns: patterns, custom_redactors: @custom_redactors)
    end
  end
end
