# frozen_string_literal: true

module Tracebook
  class CommentsController < ApplicationController
    before_action :set_interaction

    def create
      @comment = @interaction.comments.build(comment_params)
      @comment.author = current_tracebook_user_label

      if @comment.save
        redirect_to interaction_path(@interaction), notice: "Comment added"
      else
        redirect_to interaction_path(@interaction), alert: "Failed to add comment"
      end
    end

    private

    def set_interaction
      @interaction = Interaction.find(params[:interaction_id])
    end

    def comment_params
      params.require(:comment).permit(:body)
    end
  end
end
