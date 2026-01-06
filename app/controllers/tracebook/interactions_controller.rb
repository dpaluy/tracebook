# frozen_string_literal: true

module Tracebook
  class InteractionsController < ApplicationController
    include Pagy::Method

    before_action :set_interaction, only: [ :show, :review ]
    helper InteractionsHelper

    def index
      respond_to do |format|
        format.html do
          @filters = filter_params
          scope = Interaction.filtered(@filters)
          @kpis = kpis_for(scope)
          @pagy, @interactions = pagy(:offset, scope.order(created_at: :desc), limit: Tracebook.config.per_page)
          @providers = Interaction.distinct.order(:provider).pluck(:provider)
          @models = Interaction.distinct.order(:model).pluck(:model)
          @projects = Interaction.distinct.order(:project).pluck(:project).compact
          @actor_types = Interaction.where.not(actor_type: nil).distinct.order(:actor_type).pluck(:actor_type)
        end
        format.csv do
          blob = ExportJob.perform_now(format: :csv, filters: filter_params.to_h)
          send_data blob.download, filename: blob.filename.to_s, type: blob.content_type
        end
        format.any { head :not_acceptable }
      end
    end

    def show
    end

    def review
      updates = {}

      # Handle review state if provided
      if params[:review_state].present?
        state = params[:review_state].to_s
        unless Interaction.review_states.key?(state)
          redirect_to interaction_path(@interaction), alert: "Invalid review state: #{state}"
          return
        end
        updates[:review_state] = state
      end

      # Handle comment if provided
      updates[:review_comment] = params[:review_comment] if params.key?(:review_comment)

      if updates.empty?
        redirect_to interaction_path(@interaction), alert: "No changes provided"
        return
      end

      # Set reviewer metadata
      updates[:reviewed_at] = Time.current
      updates[:reviewed_by] = current_tracebook_user_label

      if @interaction.update(updates)
        redirect_to interaction_path(@interaction), notice: "Review updated"
      else
        render :show, status: :unprocessable_entity
      end
    end

    def bulk_review
      ids = Array(params[:interaction_ids])
      state = params.require(:review_state).to_s
      unless Interaction.review_states.key?(state)
        redirect_to interactions_path, alert: "Invalid review state: #{state}"
        return
      end

      Interaction.where(id: ids).update_all(review_state: Interaction.review_states.fetch(state))
      redirect_to interactions_path, notice: "Updated #{ids.size} interactions"
    end

    private

    def set_interaction
      @interaction = Interaction.find(params[:id])
    end

    def filter_params
      params.fetch(:filters, {}).permit(:provider, :model, :project, :status, :review_state, :tag, :from, :to, :actor_type, :actor_id, :session_id)
    end

    def kpis_for(scope)
      {
        total: scope.count,
        success: scope.status_success.count,
        cost_cents: scope.sum(:cost_total_cents),
        input_tokens: scope.sum(:input_tokens),
        output_tokens: scope.sum(:output_tokens),
        unique_actors: scope.where.not(actor_id: nil).select(:actor_type, :actor_id).distinct.count
      }
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
