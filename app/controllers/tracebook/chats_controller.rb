# frozen_string_literal: true

module Tracebook
  class ChatsController < ApplicationController
    include Pagy::Method

    def index
      chat_model = Tracebook.config.chat_model
      scope = chat_model.includes(:messages).order(updated_at: :desc)

      scope = apply_filters(scope)

      @pagy, @chats = pagy(:offset, scope, limit: Tracebook.config.per_page)
      @chat_stats = preload_chat_stats(@chats)
      @filters = filter_params
      @actors = load_actors(chat_model)
      @models = load_models(chat_model)
      @kpis = calculate_kpis(chat_model)
    end

    def show
      chat_model = Tracebook.config.chat_model
      @chat = chat_model.includes(messages: :model).find(params[:id])
      @messages = @chat.messages.order(created_at: :asc)
      @costs_by_message = load_message_costs(@messages)
      @review = ChatReview.find_or_initialize_by(chat: @chat)
      @comments = @review.persisted? ? @review.comments.chronological : []
      @kpis = calculate_chat_kpis(@chat)

      respond_to do |format|
        format.html
        format.json do
          send_data chat_as_json(@chat),
            type: "application/json",
            filename: "chat-#{@chat.id}.json",
            disposition: "attachment"
        end
      end
    end

    def review
      chat_model = Tracebook.config.chat_model
      chat = chat_model.find(params[:id])
      review = ChatReview.for_chat(chat)

      review.update!(
        **review_params,
        reviewed_at: Time.current
      )

      redirect_to chat_path(chat), notice: "Review updated to #{review.review_state}."
    end

    private

    def filter_params
      params.fetch(:filters, {}).permit(:actor, :model, :review_state)
    end

    def apply_filters(scope)
      filters = filter_params

      if filters[:actor].present?
        scope = scope.where(user_id: filters[:actor])
      end

      if filters[:model].present?
        scope = scope.joins(:model).where(models: { model_id: filters[:model] })
      end

      if filters[:review_state].present?
        if filters[:review_state] == "pending"
          non_pending_ids = ChatReview.where(chat_type: Tracebook.config.chat_class).where.not(review_state: :pending).pluck(:chat_id)
          scope = scope.where.not(id: non_pending_ids)
        else
          reviewed_chat_ids = ChatReview.where(
            review_state: filters[:review_state],
            chat_type: Tracebook.config.chat_class
          ).pluck(:chat_id)
          scope = scope.where(id: reviewed_chat_ids)
        end
      end

      scope
    end

    def preload_chat_stats(chats)
      chat_ids = chats.map(&:id)
      chat_class = Tracebook.config.chat_class
      message_class = Tracebook.config.message_class

      # Preload reviews
      reviews = ChatReview.where(chat_type: chat_class, chat_id: chat_ids).index_by(&:chat_id)

      # Preload costs per chat: sum via message join
      message_model = Tracebook.config.message_model
      assistant_by_chat = message_model
        .where(chat_id: chat_ids, role: "assistant")
        .group(:chat_id)
        .select("chat_id, COUNT(*) as msg_count, COALESCE(SUM(input_tokens), 0) as total_input, COALESCE(SUM(output_tokens), 0) as total_output")
        .index_by { |r| r[:chat_id] }

      message_table = message_model.table_name
      costs_by_chat = MessageCost
        .joins(
          ActiveRecord::Base.sanitize_sql_array([
            "INNER JOIN #{message_table} ON #{message_table}.id = tracebook_message_costs.message_id AND tracebook_message_costs.message_type = ?",
            message_class
          ])
        )
        .where(message_table => { chat_id: chat_ids })
        .group("#{message_table}.chat_id")
        .sum(:cost_total_cents)

      chat_ids.each_with_object({}) do |cid, hash|
        stats = assistant_by_chat[cid]
        hash[cid] = {
          review_state: reviews[cid]&.review_state || "pending",
          message_count: stats&.msg_count || 0,
          total_input: stats&.total_input || 0,
          total_output: stats&.total_output || 0,
          total_cost_cents: costs_by_chat[cid] || 0
        }
      end
    end

    def load_actors(chat_model)
      return [] unless chat_model.column_names.include?("user_id")

      user_ids = chat_model.where.not(user_id: nil).distinct.pluck(:user_id)
      return [] if user_ids.empty?

      user_class = chat_model.reflect_on_association(:user)&.klass
      return user_ids.map { |id| [ id, id ] } unless user_class

      user_class.where(id: user_ids).map { |u| [ actor_label(u), u.id ] }
    end

    def load_models(chat_model)
      return [] unless chat_model.reflect_on_association(:model)

      chat_model.joins(:model).distinct.pluck("models.model_id").sort
    end

    def actor_label(actor)
      if Tracebook.config.actor_display
        Tracebook.config.actor_display.call(actor)
      else
        actor.try(:name) || actor.try(:email) || "#{actor.class}##{actor.id}"
      end
    end

    def calculate_kpis(chat_model)
      message_model = Tracebook.config.message_model
      {
        total_chats: chat_model.count,
        total_messages: message_model.where(role: "assistant").count,
        total_cost_cents: MessageCost.sum(:cost_total_cents)
      }
    end

    def review_params
      params.permit(:review_state, :review_comment, :reviewed_by)
    end

    def load_message_costs(messages)
      assistant_ids = messages.select { |m| m.role == "assistant" }.map(&:id)
      return {} if assistant_ids.empty?

      MessageCost.where(
        message_type: Tracebook.config.message_class,
        message_id: assistant_ids
      ).index_by { |c| c.message_id.to_i }
    end

    def chat_as_json(chat)
      messages_json = @messages.map do |message|
        msg = {
          role: message.role,
          content: Tracebook.redact(message.content, scope: chat.id),
          created_at: message.created_at.iso8601
        }

        if message.role == "assistant"
          msg[:input_tokens] = message.input_tokens
          msg[:output_tokens] = message.output_tokens
          msg[:model] = message.model&.model_id

          cost = @costs_by_message[message.id]
          if cost
            msg[:cost] = {
              input_cents: cost.cost_input_cents,
              output_cents: cost.cost_output_cents,
              total_cents: cost.cost_total_cents
            }
          end
        end

        msg
      end

      review_state = @review.persisted? ? @review.review_state : "pending"

      {
        id: chat.id,
        actor: helpers.actor_name(chat),
        created_at: chat.created_at.iso8601,
        updated_at: chat.updated_at.iso8601,
        kpis: @kpis,
        review_state: review_state,
        messages: messages_json
      }.to_json
    end

    def calculate_chat_kpis(chat)
      messages = chat.messages.where(role: "assistant")
      message_ids = messages.pluck(:id)
      message_type = Tracebook.config.message_class
      costs = MessageCost.where(message_type: message_type, message_id: message_ids)

      {
        message_count: messages.count,
        total_input_tokens: messages.sum(:input_tokens),
        total_output_tokens: messages.sum(:output_tokens),
        total_cost_cents: costs.sum(:cost_total_cents)
      }
    end
  end
end
