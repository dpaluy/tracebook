# frozen_string_literal: true

module Tracebook
  module Seeds
    module PricingRules
      # All prices are in cents per 1000 tokens.
      # effective_from is set to provider's approximate release date.
      DEFAULTS = [
        # Gemini (Google)
        { provider: "gemini", model_glob: "gemini-2.0-flash*", input_cents_per_unit: 10, output_cents_per_unit: 40, effective_from: Date.new(2024, 12, 11) },
        { provider: "gemini", model_glob: "gemini-1.5-pro*", input_cents_per_unit: 125, output_cents_per_unit: 500, effective_from: Date.new(2024, 5, 14) },
        { provider: "gemini", model_glob: "gemini-1.5-flash*", input_cents_per_unit: 8, output_cents_per_unit: 30, effective_from: Date.new(2024, 5, 14) },

        # OpenAI
        { provider: "openai", model_glob: "gpt-4o", input_cents_per_unit: 250, output_cents_per_unit: 1000, effective_from: Date.new(2024, 5, 13) },
        { provider: "openai", model_glob: "gpt-4o-mini*", input_cents_per_unit: 15, output_cents_per_unit: 60, effective_from: Date.new(2024, 7, 18) },
        { provider: "openai", model_glob: "gpt-4-turbo*", input_cents_per_unit: 1000, output_cents_per_unit: 3000, effective_from: Date.new(2024, 4, 9) },

        # Anthropic
        { provider: "anthropic", model_glob: "claude-3-5-sonnet*", input_cents_per_unit: 300, output_cents_per_unit: 1500, effective_from: Date.new(2024, 6, 20) },
        { provider: "anthropic", model_glob: "claude-3-5-haiku*", input_cents_per_unit: 80, output_cents_per_unit: 400, effective_from: Date.new(2024, 10, 22) },
        { provider: "anthropic", model_glob: "claude-3-opus*", input_cents_per_unit: 1500, output_cents_per_unit: 7500, effective_from: Date.new(2024, 3, 4) },

        # Ollama (local/free)
        { provider: "ollama", model_glob: "*", input_cents_per_unit: 0, output_cents_per_unit: 0, effective_from: Date.new(2023, 1, 1) }
      ].freeze

      class << self
        # Seeds default pricing rules idempotently.
        # Uses find_or_create_by on provider + model_glob to avoid duplicates.
        #
        # @return [Hash] Summary with :created and :skipped counts
        def seed!
          created = 0
          skipped = 0

          DEFAULTS.each do |attrs|
            rule = Tracebook::PricingRule.find_or_initialize_by(
              provider: attrs[:provider],
              model_glob: attrs[:model_glob]
            )

            if rule.new_record?
              rule.assign_attributes(
                input_cents_per_unit: attrs[:input_cents_per_unit],
                output_cents_per_unit: attrs[:output_cents_per_unit],
                effective_from: attrs[:effective_from],
                currency: "USD"
              )
              rule.save!
              created += 1
            else
              skipped += 1
            end
          end

          { created:, skipped: }
        end
      end
    end
  end
end
