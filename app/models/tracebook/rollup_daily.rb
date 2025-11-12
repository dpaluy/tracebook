# frozen_string_literal: true

module Tracebook
  # Daily aggregated metrics for LLM interactions.
  #
  # Stores summarized statistics by date/provider/model/project for analytics
  # and cost reporting. Updated nightly by {DailyRollupsJob}.
  #
  # ## Fields
  # - `date` - Date of rollup (part of composite PK)
  # - `provider` - Provider name (part of composite PK)
  # - `model` - Model identifier (part of composite PK)
  # - `project` - Project name (part of composite PK, nullable)
  # - `interactions_count` - Total number of interactions
  # - `success_count` - Number of successful interactions
  # - `error_count` - Number of failed interactions
  # - `input_tokens_sum` - Sum of input tokens
  # - `output_tokens_sum` - Sum of output tokens
  # - `cost_cents_sum` - Total cost in cents
  #
  # ## Primary Key
  # Composite PK: `(date, provider, model, project)`
  #
  # @example Querying daily metrics
  #   RollupDaily
  #     .where(provider: "openai", date: Date.current)
  #     .sum(:cost_cents_sum) / 100.0 # Total cost in dollars
  #
  # @example Finding top models by cost
  #   RollupDaily
  #     .where(date: 30.days.ago..Date.current)
  #     .group(:provider, :model)
  #     .sum(:cost_cents_sum)
  #     .sort_by { |_, cents| -cents }
  #     .first(10)
  #
  # @example Error rate for a model
  #   rollup = RollupDaily.find_by(date: Date.current, provider: "openai", model: "gpt-4o")
  #   error_rate = rollup.error_count.to_f / rollup.interactions_count
  #
  # @see DailyRollupsJob
  class RollupDaily < ApplicationRecord
    self.table_name = "tracebook_rollups_dailies"

    # @!attribute [rw] interactions_count
    #   @return [Integer] Total number of interactions (default: 0)
    attribute :interactions_count, :integer, default: 0

    # @!attribute [rw] success_count
    #   @return [Integer] Number of successful interactions (default: 0)
    attribute :success_count, :integer, default: 0

    # @!attribute [rw] error_count
    #   @return [Integer] Number of failed interactions (default: 0)
    attribute :error_count, :integer, default: 0

    # @!attribute [rw] input_tokens_sum
    #   @return [Integer] Sum of input tokens across all interactions (default: 0)
    attribute :input_tokens_sum, :integer, default: 0

    # @!attribute [rw] output_tokens_sum
    #   @return [Integer] Sum of output tokens across all interactions (default: 0)
    attribute :output_tokens_sum, :integer, default: 0

    # @!attribute [rw] cost_cents_sum
    #   @return [Integer] Total cost in cents (default: 0)
    attribute :cost_cents_sum, :integer, default: 0

    validates :date, presence: true
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
