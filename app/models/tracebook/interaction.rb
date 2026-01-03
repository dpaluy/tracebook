# frozen_string_literal: true

module Tracebook
  # ActiveRecord model for LLM interactions.
  #
  # Stores all data related to an LLM API call including request/response payloads,
  # usage metrics, cost, review state, and relationships.
  #
  # ## Payload Fields
  # - `request_payload` - Full request sent to provider (JSON)
  # - `response_payload` - Full response from provider (JSON)
  # - `review_comment` - Reviewer's comments
  #
  # Note: Encryption is optional. See README for instructions on enabling
  # ActiveRecord::Encryption for these fields.
  #
  # ## Enums
  # - `status`: `:success`, `:error`, `:canceled`
  # - `review_state`: `:pending`, `:approved`, `:flagged`
  #
  # ## Associations
  # - `parent` - Parent interaction for hierarchical chains
  # - `actor` - Polymorphic association to entity who triggers LLM request (User, VendorUser, etc.)
  # - `request_payload_blob` - ActiveStorage blob for large requests
  # - `response_payload_blob` - ActiveStorage blob for large responses
  #
  # @example Finding interactions
  #   Interaction.by_provider("openai")
  #     .by_model("gpt-4o")
  #     .by_review_state(:pending)
  #     .between_dates(30.days.ago, Date.current)
  #
  # @example Filtering with parameters
  #   Interaction.filtered(
  #     provider: "anthropic",
  #     model: "claude-3-5-sonnet",
  #     review_state: "flagged",
  #     from: "2025-01-01",
  #     to: "2025-01-31"
  #   )
  class Interaction < ApplicationRecord
    self.table_name = "tracebook_interactions"

    # @!attribute [rw] parent
    #   @return [Tracebook::Interaction, nil] Parent interaction for hierarchical chains
    belongs_to :parent, class_name: "Tracebook::Interaction", optional: true

    # @!attribute [rw] comments
    #   @return [ActiveRecord::Relation<Tracebook::Comment>] Comments on this interaction
    has_many :comments, -> { chronological }, class_name: "Tracebook::Comment", dependent: :destroy

    # @!attribute [rw] actor
    #   @return [ActiveRecord::Base, nil] Polymorphic actor (User, VendorUser, etc.)
    belongs_to :actor, polymorphic: true, optional: true

    # @!attribute [rw] request_payload_blob
    #   @return [ActiveStorage::Blob, nil] Blob for large request payloads
    belongs_to :request_payload_blob, class_name: "ActiveStorage::Blob", optional: true

    # @!attribute [rw] response_payload_blob
    #   @return [ActiveStorage::Blob, nil] Blob for large response payloads
    belongs_to :response_payload_blob, class_name: "ActiveStorage::Blob", optional: true

    # @!attribute [rw] status
    #   @return [Symbol] Request status (:success, :error, :canceled)
    enum :status, { success: 0, error: 1, canceled: 2 }, prefix: true

    # @!attribute [rw] review_state
    #   @return [Symbol] Review state (:pending, :approved, :flagged)
    enum :review_state, { pending: 0, approved: 1, flagged: 2 }, prefix: true

    before_validation :generate_session_id, on: :create

    attribute :tags, :json, default: []
    attribute :metadata, :json, default: {}
    attribute :request_payload, :json, default: {}
    attribute :response_payload, :json, default: {}

    validates :provider, presence: true
    validates :model, presence: true

    scope :by_provider, ->(provider) { where(provider: provider) if provider.present? }
    scope :by_model, ->(model) { where(model: model) if model.present? }
    scope :by_project, ->(project) { where(project: project) if project.present? }
    scope :by_status, ->(status) { where(status: status) if status.present? }
    scope :by_review_state, ->(state) { where(review_state: state) if state.present? }
    scope :between_dates, ->(from, to) {
      scope = all
      scope = scope.where("created_at >= ?", Date.parse(from.to_s).beginning_of_day) if from.present?
      scope = scope.where("created_at <= ?", Date.parse(to.to_s).end_of_day) if to.present?
      scope
    }
    scope :tagged_with, ->(tag) {
      where("tags LIKE ?", "%#{sanitize_sql_like(tag)}%") if tag.present?
    }
    scope :by_actor_type, ->(type) { where(actor_type: type) if type.present? }
    scope :by_actor_id, ->(id) { where(actor_id: id) if id.present? }
    scope :by_actor, ->(type, id) { by_actor_type(type).by_actor_id(id) }
    scope :by_session, ->(session_id) { where(session_id: session_id) if session_id.present? }

    def self.filtered(params)
      by_provider(params[:provider])
        .by_model(params[:model])
        .by_project(params[:project])
        .by_status(params[:status])
        .by_review_state(params[:review_state])
        .by_actor_type(params[:actor_type])
        .by_actor_id(params[:actor_id])
        .by_session(params[:session_id])
        .tagged_with(params[:tag])
        .between_dates(params[:from], params[:to])
    end

    # Human-readable context label from metadata
    def context_label
      metadata&.dig("context_label") || session_id&.truncate(20) || "(no context)"
    end

    private

    def generate_session_id
      self.session_id ||= "tb_#{SecureRandom.uuid}"
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
