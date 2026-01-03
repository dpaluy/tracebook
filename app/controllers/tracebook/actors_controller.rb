# frozen_string_literal: true

module Tracebook
  class ActorsController < ApplicationController
    helper InteractionsHelper

    PER_PAGE = 25

    def index
      all_actors = aggregate_actors_with_stats
      @actors, @pagination = paginate_array(all_actors)
      @kpis = calculate_global_kpis
    end

    def show
      @actor_type = type_from_param(params[:type])
      @actor_id = params[:id].to_i
      all_sessions = LlmSession.for_actor(@actor_type, @actor_id)
      @sessions, @pagination = paginate_array(all_sessions)
      @kpis = calculate_actor_kpis(@actor_type, @actor_id)
    end

    def llm_session
      @actor_type = type_from_param(params[:type])
      @actor_id = params[:id].to_i
      @llm_session = LlmSession.find(@actor_type, @actor_id, params[:session_id])
      @interactions = @llm_session.interactions
      @kpis = calculate_session_kpis(@llm_session)
    end

    private

    def paginate_array(array)
      page = (params[:page] || 1).to_i
      total = array.size
      total_pages = (total.to_f / PER_PAGE).ceil
      page = [[page, 1].max, [total_pages, 1].max].min

      offset = (page - 1) * PER_PAGE
      items = array[offset, PER_PAGE] || []

      pagination = {
        current_page: page,
        total_pages: total_pages,
        total_count: total,
        per_page: PER_PAGE,
        prev_page: page > 1 ? page - 1 : nil,
        next_page: page < total_pages ? page + 1 : nil
      }

      [ items, pagination ]
    end

    def type_from_param(param)
      # Validate format: only lowercase letters, numbers, and underscores allowed
      raise ActiveRecord::RecordNotFound unless param.match?(/\A[a-z0-9_]+\z/)

      candidate = param.singularize.camelize
      allowed_types = Interaction.where.not(actor_type: nil).distinct.pluck(:actor_type)

      raise ActiveRecord::RecordNotFound unless allowed_types.include?(candidate)

      candidate
    end

    def type_to_param(type)
      type.underscore.pluralize
    end
    helper_method :type_to_param

    def aggregate_actors_with_stats
      rows = Interaction
        .where.not(actor_type: nil)
        .group(:actor_type, :actor_id)
        .select(
          "actor_type, actor_id",
          "COUNT(DISTINCT session_id) as sessions_count",
          "COUNT(*) as interactions_count",
          "SUM(total_tokens) as total_tokens",
          "SUM(cost_total_cents) as total_cost_cents",
          "MAX(created_at) as last_activity"
        )
        .order("last_activity DESC")

      rows.map do |row|
        {
          actor_type: row.actor_type,
          actor_id: row.actor_id,
          sessions_count: row.sessions_count,
          interactions_count: row.interactions_count,
          total_tokens: row.total_tokens || 0,
          total_cost_cents: row.total_cost_cents || 0,
          last_activity: row.last_activity.is_a?(String) ? Time.zone.parse(row.last_activity) : row.last_activity
        }
      end
    end

    def calculate_global_kpis
      {
        total_actors: Interaction.where.not(actor_type: nil).distinct.count(:actor_id),
        total_sessions: Interaction.distinct.count(:session_id),
        total_tokens: Interaction.sum(:total_tokens),
        total_cost_cents: Interaction.sum(:cost_total_cents)
      }
    end

    def calculate_actor_kpis(actor_type, actor_id)
      interactions = Interaction.where(actor_type: actor_type, actor_id: actor_id)
      {
        sessions_count: interactions.distinct.count(:session_id),
        interactions_count: interactions.count,
        total_tokens: interactions.sum(:total_tokens),
        total_cost_cents: interactions.sum(:cost_total_cents)
      }
    end

    def calculate_session_kpis(session)
      {
        interactions_count: session.interactions_count,
        total_tokens: session.total_tokens,
        input_tokens: session.interactions.sum(:input_tokens),
        output_tokens: session.interactions.sum(:output_tokens),
        total_cost_cents: session.total_cost_cents,
        avg_latency_ms: session.avg_latency_ms
      }
    end
  end
end
