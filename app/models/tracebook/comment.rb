# frozen_string_literal: true

module Tracebook
  class Comment < ApplicationRecord
    self.table_name = "tracebook_comments"

    belongs_to :chat_review, class_name: "Tracebook::ChatReview"

    validates :author, presence: true
    validates :body, presence: true

    scope :chronological, -> { order(created_at: :asc) }
  end
end
