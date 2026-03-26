# frozen_string_literal: true

module Tracebook
  class ChatReview < ApplicationRecord
    self.table_name = "tracebook_chat_reviews"

    belongs_to :chat, polymorphic: true, optional: true
    has_many :comments, class_name: "Tracebook::Comment", dependent: :destroy

    enum :review_state, { pending: 0, approved: 1, flagged: 2 }, prefix: true

    validates :chat_type, presence: true
    validates :chat_id, presence: true

    def self.for_chat(chat)
      find_or_create_by!(chat: chat)
    end
  end
end
