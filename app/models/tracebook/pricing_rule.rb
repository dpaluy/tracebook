# frozen_string_literal: true

module Tracebook
  # Pricing rule for calculating LLM interaction costs.
  #
  # Defines cost in cents per 1,000,000 tokens for a provider/model pattern.
  # Supports glob patterns for matching multiple models and date-based effective periods.
  #
  # ## Fields
  # - `provider` - Provider name (e.g., "openai", "anthropic")
  # - `model_glob` - Glob pattern for matching models (e.g., "gpt-4o*", "claude-3-5-*")
  # - `input_cents_per_unit` - Cost in cents per 1M input tokens (decimal)
  # - `output_cents_per_unit` - Cost in cents per 1M output tokens (decimal)
  # - `currency` - Currency code (e.g., "USD")
  # - `effective_from` - Date this pricing takes effect
  # - `effective_to` - Optional end date for this pricing
  #
  # @example Creating pricing rules
  #   PricingRule.create!(
  #     provider: "openai",
  #     model_glob: "gpt-4o",
  #     input_cents_per_unit: 250,    # $2.50/1M tokens
  #     output_cents_per_unit: 1000,  # $10.00/1M tokens
  #     currency: "USD",
  #     effective_from: Date.new(2024, 8, 6)
  #   )
  #
  # @example Glob patterns
  #   # Exact match
  #   model_glob: "gpt-4o"
  #
  #   # All GPT-4o variants
  #   model_glob: "gpt-4o*"
  #
  #   # All Claude 3.5 models
  #   model_glob: "claude-3-5-*"
  #
  #   # Fallback for any model
  #   model_glob: "*"
  #
  # @example Finding applicable rule
  #   rule = PricingRule
  #     .where(provider: "openai")
  #     .where("? >= effective_from", Date.current)
  #     .where("effective_to IS NULL OR ? < effective_to", Date.current)
  #     .find { |r| r.matches_model?("gpt-4o-mini") }
  class PricingRule < ApplicationRecord
    self.table_name = "tracebook_pricing_rules"

    validates :provider, presence: true
    validates :model_glob, presence: true
    validates :effective_from, presence: true

    # Returns true if this rule is active on the given date.
    #
    # @param date [Date] The date to check
    # @return [Boolean] true if rule is effective on this date
    #
    # @example
    #   rule.active_on?(Date.current) # => true
    #   rule.active_on?(Date.new(2020, 1, 1)) # => false
    def active_on?(date)
      date >= effective_from && (effective_to.nil? || date < effective_to)
    end

    # Returns true if this rule's glob pattern matches the given model.
    #
    # Uses case-insensitive file glob matching.
    #
    # @param model [String] Model identifier to match
    # @return [Boolean] true if pattern matches
    #
    # @example
    #   rule = PricingRule.new(model_glob: "gpt-4o*")
    #   rule.matches_model?("gpt-4o") # => true
    #   rule.matches_model?("gpt-4o-mini") # => true
    #   rule.matches_model?("claude-3-5-sonnet") # => false
    def matches_model?(model)
      File.fnmatch?(model_glob, model, File::FNM_CASEFOLD)
    end
  end
end
