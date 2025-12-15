# frozen_string_literal: true

module Tracebook
  class InteractionsController < ApplicationController
    include Pagy::Method

    before_action :set_interaction, only: [ :show, :review ]
    helper InteractionsHelper

    def index
      @filters = filter_params
      scope = Interaction.filtered(@filters)
      @kpis = kpis_for(scope)
      @pagy, @interactions = pagy(scope.order(created_at: :desc), limit: Tracebook.config.per_page, request: request)
      @providers = Interaction.distinct.order(:provider).pluck(:provider)
      @models = Interaction.distinct.order(:model).pluck(:model)
      @projects = Interaction.distinct.order(:project).pluck(:project).compact
    end

    def show
    end

    def review
      state = params.require(:review_state).to_s
      unless Interaction.review_states.key?(state)
        redirect_to interaction_path(@interaction), alert: "Invalid review state: #{state}"
        return
      end

      if @interaction.update(review_state: state)
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
      params.fetch(:filters, {}).permit(:provider, :model, :project, :status, :review_state, :tag, :from, :to)
    end

    def kpis_for(scope)
      {
        total: scope.count,
        success: scope.status_success.count,
        cost_cents: scope.sum(:cost_total_cents),
        input_tokens: scope.sum(:input_tokens),
        output_tokens: scope.sum(:output_tokens)
      }
    end
  end
end

TraceBook = Tracebook unless defined?(TraceBook)
