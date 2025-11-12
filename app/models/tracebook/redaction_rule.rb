# frozen_string_literal: true

module Tracebook
  # Rule for redacting PII from interaction payloads.
  #
  # Defines a regex pattern to detect and replace sensitive data before
  # persistence. Runs on request, response, or both payloads.
  #
  # ## Fields
  # - `name` - Human-readable name for this rule
  # - `pattern` - Regular expression pattern to match
  # - `replacement` - Replacement string (e.g., "[REDACTED]", "[EMAIL]")
  # - `applies_to` - Where to apply: `:request`, `:response`, `:both`, `:metadata`
  # - `enabled` - Whether this rule is active
  #
  # ## Built-in Rules
  # TraceBook includes default redactors for:
  # - Email addresses
  # - Phone numbers (US format)
  # - Credit card PANs
  #
  # @example Creating a custom redaction rule
  #   RedactionRule.create!(
  #     name: "API Keys",
  #     pattern: 'api_key["\s]*[:=]["\s]*\K[\w-]+',
  #     replacement: "[API_KEY]",
  #     applies_to: :both,
  #     enabled: true
  #   )
  #
  # @example Email redaction
  #   RedactionRule.create!(
  #     name: "Email Addresses",
  #     pattern: '\b[\w\.-]+@[\w\.-]+\.\w{2,}\b',
  #     replacement: "[EMAIL]",
  #     applies_to: :both,
  #     enabled: true
  #   )
  #
  # @example SSN redaction
  #   RedactionRule.create!(
  #     name: "Social Security Numbers",
  #     pattern: '\b\d{3}-\d{2}-\d{4}\b',
  #     replacement: "[SSN]",
  #     applies_to: :both,
  #     enabled: true
  #   )
  #
  # @see Redactors::Email
  # @see Redactors::Phone
  # @see Redactors::CardPAN
  class RedactionRule < ApplicationRecord
    self.table_name = "tracebook_redaction_rules"

    # @!attribute [rw] applies_to
    #   @return [Symbol] Where to apply redaction (:request, :response, :both, :metadata)
    enum :applies_to, { request: 0, response: 1, both: 2, metadata: 3 }

    validates :name, presence: true
    validates :pattern, presence: true
    validates :replacement, presence: true

    # Returns the compiled regex pattern.
    #
    # Caches the compiled pattern for performance. If pattern is invalid,
    # falls back to escaped literal match.
    #
    # @return [Regexp] Compiled regular expression with MULTILINE flag
    #
    # @example
    #   rule = RedactionRule.new(pattern: '\b\d{3}-\d{2}-\d{4}\b')
    #   rule.compiled_pattern.match("123-45-6789") # => MatchData
    def compiled_pattern
      @compiled_pattern ||= Regexp.new(pattern, Regexp::MULTILINE)
    rescue RegexpError
      Regexp.new(Regexp.escape(pattern.to_s))
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
