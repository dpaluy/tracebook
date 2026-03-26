# frozen_string_literal: true

module Tracebook
  module Redaction
    # A single redaction pattern with regex, replacement, and optional validator.
    Pattern = Data.define(:name, :regex, :replacement, :validator) do
      def initialize(name:, regex:, replacement:, validator: nil)
        super
      end

      def redact(text)
        return text unless text.is_a?(String)

        text.gsub(regex) do |match|
          if validator && !validator.call(match)
            match
          else
            replacement
          end
        end
      end
    end

    # Luhn algorithm for credit card validation
    LUHN = ->(number) {
      digits = number.gsub(/\D/, "")
      return false if digits.length < 13 || digits.length > 19

      sum = 0
      digits.reverse.each_char.with_index do |d, i|
        n = d.to_i
        n *= 2 if i.odd?
        n -= 9 if n > 9
        sum += n
      end
      (sum % 10).zero?
    }

    PATTERNS = {
      email: Pattern.new(
        name: :email,
        regex: /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/,
        replacement: "[EMAIL]"
      ),
      phone: Pattern.new(
        name: :phone,
        regex: /(?<!\d)\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b/,
        replacement: "[PHONE]"
      ),
      ssn: Pattern.new(
        name: :ssn,
        regex: /\b\d{3}-\d{2}-\d{4}\b/,
        replacement: "[SSN]",
        validator: ->(match) {
          area = match[0..2].to_i
          area > 0 && area != 666 && area < 900
        }
      ),
      credit_card: Pattern.new(
        name: :credit_card,
        regex: /\b(?:\d[ -]*?){13,19}\b/,
        replacement: "[CREDIT_CARD]",
        validator: LUHN
      ),
      openai_key: Pattern.new(
        name: :openai_key,
        regex: /\bsk-[A-Za-z0-9_-]{20,}\b/,
        replacement: "[KEY]"
      ),
      anthropic_key: Pattern.new(
        name: :anthropic_key,
        regex: /\bsk-ant-[A-Za-z0-9_-]{20,}\b/,
        replacement: "[KEY]"
      ),
      aws_key: Pattern.new(
        name: :aws_key,
        regex: /\bAKIA[0-9A-Z]{16}\b/,
        replacement: "[KEY]"
      ),
      stripe_key: Pattern.new(
        name: :stripe_key,
        regex: /\b[sr]k_(test|live)_[A-Za-z0-9]{20,}\b/,
        replacement: "[KEY]"
      ),
      github_token: Pattern.new(
        name: :github_token,
        regex: /\bgh[pousr]_[A-Za-z0-9_]{36,}\b/,
        replacement: "[KEY]"
      ),
      bearer_token: Pattern.new(
        name: :bearer_token,
        regex: /Bearer\s+[A-Za-z0-9\-._~+\/]+=*/i,
        replacement: "Bearer [REDACTED]"
      ),
      jwt: Pattern.new(
        name: :jwt,
        regex: /\beyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/,
        replacement: "[JWT]"
      ),
      ipv4: Pattern.new(
        name: :ipv4,
        regex: /\b(?:\d{1,3}\.){3}\d{1,3}\b/,
        replacement: "[IP_ADDRESS]",
        validator: ->(match) {
          match.split(".").all? { |octet| octet.to_i.between?(0, 255) }
        }
      ),
      private_key: Pattern.new(
        name: :private_key,
        regex: /-----BEGIN [A-Z ]+ PRIVATE KEY-----.*?-----END [A-Z ]+ PRIVATE KEY-----/m,
        replacement: "[PRIVATE_KEY]"
      )
    }.freeze

    GROUPS = {
      pii: %i[email phone ssn],
      financial: %i[credit_card],
      api_keys: %i[openai_key anthropic_key aws_key stripe_key github_token],
      auth: %i[bearer_token jwt],
      network: %i[ipv4],
      crypto: %i[private_key]
    }.freeze
  end
end
