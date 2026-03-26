# frozen_string_literal: true

module Tracebook
  class CommentsController < ApplicationController
    def create
      chat = Tracebook.config.chat_model.find(params[:chat_id])
      review = ChatReview.for_chat(chat)

      comment = review.comments.build(comment_params)
      comment.author = current_tracebook_user_label

      if comment.save
        redirect_to chat_path(chat), notice: "Comment added"
      else
        redirect_to chat_path(chat), alert: "Failed to add comment"
      end
    end

    private

    def comment_params
      params.require(:comment).permit(:body)
    end
  end
end
