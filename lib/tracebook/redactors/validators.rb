# frozen_string_literal: true

module Tracebook
  module Redactors
    # Validation methods for PII detection.
    #
    # Provides Luhn algorithm for credit card validation and SSN range validation.
    # Used by Pattern class to reduce false positives in PII detection.
    module Validators
      module_function

      # Validates a credit card number using the Luhn algorithm.
      #
      # The Luhn algorithm (mod 10) is used to validate credit card numbers.
      # It detects single-digit errors and most transpositions.
      #
      # @param digits [String] The credit card number (digits only, no spaces/dashes)
      # @return [Boolean] true if the checksum is valid
      #
      # @example
      #   Validators.luhn("4532015112830366") # => true (valid Visa)
      #   Validators.luhn("1234567890123456") # => false (invalid checksum)
      def luhn(digits)
        return false if digits.nil? || digits.empty?
        return false unless digits.match?(/\A\d+\z/)
        return false if digits.length < 13 || digits.length > 19
        return false if digits.chars.uniq.size == 1 # Reject repeated digits (e.g., all zeros)

        sum = 0
        digits.reverse.each_char.with_index do |char, index|
          digit = char.to_i
          if index.odd?
            doubled = digit * 2
            digit = doubled > 9 ? doubled - 9 : doubled
          end
          sum += digit
        end

        (sum % 10).zero?
      end

      # Validates an SSN area number (first 3 digits).
      #
      # The Social Security Administration has specific rules for valid area numbers:
      # - 000 is never valid
      # - 666 is never valid
      # - 900-999 were never issued (reserved for advertising/promotional use)
      #
      # @param area [String] The first 3 digits of an SSN
      # @return [Boolean] true if the area number could be valid
      #
      # @example
      #   Validators.ssn_range("078") # => true (valid area)
      #   Validators.ssn_range("000") # => false (invalid)
      #   Validators.ssn_range("666") # => false (invalid)
      #   Validators.ssn_range("900") # => false (invalid - promotional range)
      def ssn_range(area)
        return false if area.nil? || area.empty?
        return false unless area.match?(/\A\d{3}\z/)

        area_num = area.to_i

        # Invalid ranges per SSA rules
        return false if area_num.zero?        # 000 never valid
        return false if area_num == 666       # 666 never valid
        return false if area_num >= 900       # 900-999 never issued

        true
      end
    end
  end
end
