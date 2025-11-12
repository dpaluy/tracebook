# frozen_string_literal: true

module Tracebook
  # Background job for aggregating daily metrics.
  #
  # Summarizes interactions by date/provider/model/project into {RollupDaily}
  # records for analytics and cost reporting. Should be scheduled nightly for
  # each active provider/model combination.
  #
  # ## Aggregated Metrics
  # - Total interaction count
  # - Success/error counts
  # - Input/output token sums
  # - Total cost in cents
  #
  # @example Schedule with Sidekiq Cron
  #   Sidekiq::Cron::Job.create(
  #     name: "TraceBook OpenAI rollups",
  #     cron: "0 2 * * *",
  #     class: "Tracebook::DailyRollupsJob",
  #     kwargs: { date: Date.yesterday, provider: "openai", model: nil, project: nil }
  #   )
  #
  # @example Run manually for specific date/model
  #   DailyRollupsJob.perform_now(
  #     date: Date.yesterday,
  #     provider: "openai",
  #     model: "gpt-4o",
  #     project: "support"
  #   )
  #
  # @see RollupDaily
  class DailyRollupsJob < ApplicationJob
    # Aggregates metrics for a specific date/provider/model/project.
    #
    # Creates or updates a {RollupDaily} record with summarized statistics.
    #
    # @param date [Date] Date to aggregate (usually Date.yesterday)
    # @param provider [String] Provider name (e.g., "openai")
    # @param model [String, nil] Model identifier (nil for all models)
    # @param project [String, nil] Project name (nil for all projects)
    #
    # @return [void]
    #
    # @raise [ActiveRecord::RecordInvalid] if rollup fails validation
    def perform(date:, provider:, model:, project: nil)
      scope = Interaction.where(provider: provider, model: model)
      scope = scope.where(project: project) if project
      scope = scope.where(created_at: date.beginning_of_day..date.end_of_day)

      counts = normalize_status_counts(scope.group(:status).count)
      tokens = scope.pluck(Arel.sql("COALESCE(input_tokens, 0)"), Arel.sql("COALESCE(output_tokens, 0)"))
      costs = scope.pluck(Arel.sql("COALESCE(cost_total_cents, 0)"))

      input_sum = tokens.sum { |(input, _)| input.to_i }
      output_sum = tokens.sum { |(_, output)| output.to_i }
      cost_sum = costs.sum(&:to_i)

      rollup = RollupDaily.find_or_initialize_by(date: date, provider: provider, model: model, project: project)
      rollup.interactions_count = scope.count
      rollup.success_count = counts.fetch("success", 0)
      rollup.error_count = counts.fetch("error", 0)
      rollup.input_tokens_sum = input_sum
      rollup.output_tokens_sum = output_sum
      rollup.cost_cents_sum = cost_sum
      rollup.currency = determine_currency(scope) || rollup.currency
      rollup.save!
    end

    private

    def normalize_status_counts(counts)
      counts.each_with_object(Hash.new(0)) do |(raw_key, count), normalized|
        status_name = status_name_for(raw_key)
        next unless status_name

        normalized[status_name] += count
      end
    end

    def status_name_for(raw_key)
      key_string = raw_key.to_s
      return key_string if Interaction.statuses.key?(key_string)

      integer_string?(key_string) ? Interaction.statuses.invert[key_string.to_i] : nil
    end

    def integer_string?(value)
      value.match?(/\A-?\d+\z/)
    end

    def determine_currency(scope)
      scope.pick(:currency)
    rescue NoMethodError
      scope.first&.currency
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
