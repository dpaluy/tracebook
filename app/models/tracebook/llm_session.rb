# frozen_string_literal: true

module Tracebook
  # Virtual model representing a group of LLM interactions by session_id.
  #
  # This is a query pattern, not a database table. Sessions are derived
  # from grouping interactions by (actor_type, actor_id, session_id).
  #
  # @example Finding sessions for an actor
  #   sessions = Tracebook::LlmSession.for_actor("User", 123)
  #   sessions.each do |session|
  #     puts "#{session.context_label}: #{session.interactions_count} calls"
  #   end
  class LlmSession
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :session_id, :string
    attribute :actor_type, :string
    attribute :actor_id, :integer
    attribute :context_label, :string
    attribute :model, :string
    attribute :interactions_count, :integer, default: 0
    attribute :total_tokens, :integer, default: 0
    attribute :total_cost_cents, :integer, default: 0
    attribute :avg_latency_ms, :float, default: 0.0
    attribute :pending_count, :integer, default: 0
    attribute :approved_count, :integer, default: 0
    attribute :flagged_count, :integer, default: 0
    attribute :last_activity, :datetime

    # Find all sessions for a given actor
    #
    # @param actor_type [String] Class name of actor (e.g., "User", "VendorUser")
    # @param actor_id [Integer] ID of the actor
    # @return [Array<LlmSession>] Sessions with aggregated stats
    def self.for_actor(actor_type, actor_id)
      rows = Interaction
        .where(actor_type: actor_type, actor_id: actor_id)
        .group(:session_id)
        .select(
          "session_id",
          "COUNT(*) as interactions_count",
          "SUM(total_tokens) as total_tokens",
          "SUM(cost_total_cents) as total_cost_cents",
          "AVG(latency_ms) as avg_latency_ms",
          "SUM(CASE WHEN review_state = 0 THEN 1 ELSE 0 END) as pending_count",
          "SUM(CASE WHEN review_state = 1 THEN 1 ELSE 0 END) as approved_count",
          "SUM(CASE WHEN review_state = 2 THEN 1 ELSE 0 END) as flagged_count",
          "MAX(created_at) as last_activity",
          "MIN(model) as model"
        )
        .order("last_activity DESC")

      session_ids = rows.map(&:session_id)
      context_labels = latest_context_labels_for_sessions(actor_type, actor_id, session_ids)

      rows.map do |row|
        new(
          session_id: row.session_id,
          actor_type: actor_type,
          actor_id: actor_id,
          context_label: context_labels[row.session_id],
          model: row.model,
          interactions_count: row.interactions_count,
          total_tokens: row.total_tokens || 0,
          total_cost_cents: row.total_cost_cents || 0,
          avg_latency_ms: row.avg_latency_ms || 0,
          pending_count: row.pending_count || 0,
          approved_count: row.approved_count || 0,
          flagged_count: row.flagged_count || 0,
          last_activity: row.last_activity
        )
      end
    end

    # Fetch context_label from the latest interaction per session in a single query
    # Uses ROW_NUMBER() window function to find the most recent interaction per session
    #
    # @param actor_type [String]
    # @param actor_id [Integer]
    # @param session_ids [Array<String>]
    # @return [Hash{String => String}] session_id => context_label
    def self.latest_context_labels_for_sessions(actor_type, actor_id, session_ids)
      return {} if session_ids.empty?

      # Use a subquery with ROW_NUMBER to get the latest interaction per session
      subquery = Interaction
        .where(actor_type: actor_type, actor_id: actor_id, session_id: session_ids)
        .select(
          "session_id",
          "metadata",
          "ROW_NUMBER() OVER (PARTITION BY session_id ORDER BY created_at DESC, id DESC) as rn"
        )

      # Wrap in outer query to filter rn = 1
      latest = Interaction
        .from("(#{subquery.to_sql}) AS ranked")
        .where("ranked.rn = 1")
        .select("ranked.session_id", "ranked.metadata")

      latest.each_with_object({}) do |row, hash|
        metadata = if row.metadata.is_a?(String)
          begin
            JSON.parse(row.metadata)
          rescue JSON::ParserError
            {}
          end
        else
          row.metadata || {}
        end
        hash[row.session_id] = metadata["context_label"]
      end
    end
    private_class_method :latest_context_labels_for_sessions

    # Find a specific session
    #
    # @param actor_type [String] Class name of actor
    # @param actor_id [Integer] ID of the actor
    # @param session_id [String] Session identifier
    # @return [LlmSession, nil] Session or nil if not found
    def self.find(actor_type, actor_id, session_id)
      for_actor(actor_type, actor_id).find { |s| s.session_id == session_id }
    end

    # Get all interactions for this session
    #
    # @return [ActiveRecord::Relation<Interaction>]
    def interactions
      Interaction.where(
        actor_type: actor_type,
        actor_id: actor_id,
        session_id: session_id
      ).order(created_at: :asc)
    end

    # Review state summary for display
    #
    # @return [Symbol] :all_approved, :has_flagged, :has_pending
    def review_summary
      return :has_flagged if flagged_count.positive?
      return :has_pending if pending_count.positive?

      :all_approved
    end

    # Format cost as dollars
    #
    # @return [String] e.g., "$3.20"
    def formatted_cost
      "$#{(total_cost_cents / 100.0).round(2)}"
    end

    # Format average latency
    #
    # @return [String] e.g., "1.2s"
    def formatted_latency
      "#{(avg_latency_ms / 1000.0).round(1)}s"
    end
  end
end
