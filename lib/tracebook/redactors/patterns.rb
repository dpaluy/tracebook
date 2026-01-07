# frozen_string_literal: true

require_relative "validators"

module Tracebook
  module Redactors
    # Pattern class for PII redaction with audit support.
    #
    # Wraps a regex pattern with optional validation and provides a consistent
    # call(text, audit:) interface for redaction operations.
    #
    # @attr_reader regex [Regexp] The pattern to match
    # @attr_reader replacement [String] The replacement text (e.g., "[EMAIL]")
    # @attr_reader name [String] Human-readable pattern name for audit trails
    # @attr_reader validator [Proc, nil] Optional validation proc for matched text
    #
    # @example Basic pattern usage
    #   pattern = Pattern.new(
    #     regex: /\b[\w.+-]+@[\w.-]+\.[a-z]{2,}\b/i,
    #     replacement: "[EMAIL]",
    #     name: "email"
    #   )
    #   audit = RedactionAudit.new
    #   result = pattern.call("Contact: user@example.com", audit: audit)
    #   # result => "Contact: [EMAIL]"
    #   # audit.redaction_count => 1
    #
    # @example Pattern with validator
    #   pattern = Pattern.new(
    #     regex: /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/,
    #     replacement: "[CARD]",
    #     name: "credit_card",
    #     validator: ->(match) { Validators.luhn(match.gsub(/[\s-]/, "")) }
    #   )
    #
    class Pattern
      attr_reader :regex, :replacement, :name, :validator

      def initialize(regex:, replacement:, name:, validator: nil)
        @regex = regex
        @replacement = replacement
        @name = name
        @validator = validator
      end

      # Apply pattern to text and record redactions to audit.
      #
      # @param text [String] The text to redact
      # @param audit [RedactionAudit] Audit object to record redactions
      # @param field_path [String] Optional field path for audit trail
      # @return [Array<String, RedactionAudit>] Tuple of [redacted_text, updated_audit]
      #
      def call(text, audit:, field_path: nil)
        return [ text, audit ] unless text.is_a?(String)

        result_text = text.dup
        updated_audit = audit

        # Find all matches and process in reverse order to preserve positions
        matches = []
        text.scan(regex) do
          match = Regexp.last_match
          matches << { text: match[0], start: match.begin(0), end: match.end(0) }
        end

        matches.reverse_each do |match_info|
          matched_text = match_info[:text]

          # Skip if validator fails
          next if validator && !validator.call(matched_text)

          # Perform replacement
          result_text[match_info[:start]...match_info[:end]] = replacement

          # Record to audit
          path = field_path || "inline"
          updated_audit = updated_audit.record_redaction(name, path)
        end

        [ result_text, updated_audit ]
      end
    end

    # Standard PII patterns for redaction.
    #
    # Each pattern includes a regex, replacement marker, name for audit trails,
    # and optional validator to reduce false positives.
    PATTERNS = {
      # Email addresses - RFC 5322 simplified
      email: Pattern.new(
        regex: /\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b/,
        replacement: "[EMAIL]",
        name: "email"
      ),

      # Phone numbers - US and international formats
      # Matches: (123) 456-7890, 123-456-7890, +1-123-456-7890, +44 20 7946 0958
      phone: Pattern.new(
        regex: /(?:\+\d{1,3}[\s.-]?)?\(?\d{2,4}\)?[\s.-]?\d{3,4}[\s.-]?\d{4}\b/,
        replacement: "[PHONE]",
        name: "phone"
      ),

      # Credit card numbers with Luhn validation
      # Matches: 4532015112830366, 4532-0151-1283-0366, 4532 0151 1283 0366
      credit_card: Pattern.new(
        regex: /\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/,
        replacement: "[CARD]",
        name: "credit_card",
        validator: ->(match) { Validators.luhn(match.gsub(/[\s-]/, "")) }
      ),

      # Social Security Numbers with range validation
      # Matches: 123-45-6789, 123 45 6789, 123456789
      ssn: Pattern.new(
        regex: /\b(\d{3})[\s-]?(\d{2})[\s-]?(\d{4})\b/,
        replacement: "[SSN]",
        name: "ssn",
        validator: ->(match) {
          area = match.gsub(/[\s-]/, "")[0, 3]
          Validators.ssn_range(area)
        }
      ),

      # OpenAI API keys - sk-... format
      openai_key: Pattern.new(
        regex: /\bsk-[a-zA-Z0-9]{20,}\b/,
        replacement: "[OPENAI_KEY]",
        name: "openai_key"
      ),

      # Anthropic API keys - sk-ant-... format
      anthropic_key: Pattern.new(
        regex: /\bsk-ant-[a-zA-Z0-9-]{20,}\b/,
        replacement: "[ANTHROPIC_KEY]",
        name: "anthropic_key"
      ),

      # AWS access keys - AKIA... format (20 chars)
      aws_key: Pattern.new(
        regex: /\b(?:AKIA|ABIA|ACCA|ASIA)[A-Z0-9]{16}\b/,
        replacement: "[AWS_KEY]",
        name: "aws_key"
      ),

      # Stripe API keys - sk_live_..., sk_test_..., pk_live_..., pk_test_...
      stripe_key: Pattern.new(
        regex: /\b[sp]k_(?:live|test)_[a-zA-Z0-9]{24,}\b/,
        replacement: "[STRIPE_KEY]",
        name: "stripe_key"
      ),

      # GitHub tokens - ghp_... format (fine-grained PATs)
      github_token: Pattern.new(
        regex: /\bghp_[a-zA-Z0-9]{36}\b/,
        replacement: "[GITHUB_TOKEN]",
        name: "github_token"
      ),

      # GitHub PATs - github_pat_... format
      github_pat: Pattern.new(
        regex: /\bgithub_pat_[a-zA-Z0-9]{22}_[a-zA-Z0-9]{59}\b/,
        replacement: "[GITHUB_PAT]",
        name: "github_pat"
      ),

      # Bearer tokens in headers
      bearer_token: Pattern.new(
        regex: /\bBearer\s+[a-zA-Z0-9._-]{20,}\b/i,
        replacement: "[BEARER_TOKEN]",
        name: "bearer_token"
      ),

      # Basic auth credentials - base64 encoded user:pass
      basic_auth: Pattern.new(
        regex: /\bBasic\s+[a-zA-Z0-9+\/]{20,}={0,2}/i,
        replacement: "[BASIC_AUTH]",
        name: "basic_auth"
      ),

      # PEM private keys
      private_key: Pattern.new(
        regex: /-----BEGIN\s+(?:RSA\s+)?PRIVATE\s+KEY-----[\s\S]*?-----END\s+(?:RSA\s+)?PRIVATE\s+KEY-----/,
        replacement: "[PRIVATE_KEY]",
        name: "private_key"
      ),

      # IPv4 addresses
      ipv4: Pattern.new(
        regex: /\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/,
        replacement: "[IPV4]",
        name: "ipv4"
      ),

      # IPv6 addresses - full and compressed formats
      ipv6: Pattern.new(
        regex: /\b(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\b|\b(?:[0-9a-fA-F]{1,4}:){1,7}:\b|\b(?:[0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}\b|::(?:[0-9a-fA-F]{1,4}:){0,5}[0-9a-fA-F]{1,4}\b|::1\b/,
        replacement: "[IPV6]",
        name: "ipv6"
      ),

      # JSON Web Tokens (JWT) - three base64url segments
      jwt: Pattern.new(
        regex: /\beyJ[a-zA-Z0-9_-]*\.eyJ[a-zA-Z0-9_-]*\.[a-zA-Z0-9_-]+\b/,
        replacement: "[JWT]",
        name: "jwt"
      )
    }.freeze

    # Pattern groups for convenient batch enabling
    PATTERN_GROUPS = {
      pii: %i[email phone ssn],
      financial: %i[credit_card],
      api_keys: %i[openai_key anthropic_key aws_key stripe_key github_token github_pat],
      auth: %i[bearer_token basic_auth jwt],
      network: %i[ipv4 ipv6],
      crypto: %i[private_key]
    }.freeze
  end
end
