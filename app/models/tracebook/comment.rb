# frozen_string_literal: true

module Tracebook
  class Comment < ApplicationRecord
    self.table_name = "tracebook_comments"

    belongs_to :interaction, class_name: "Tracebook::Interaction"

    validates :author, presence: true
    validates :body, presence: true

    scope :chronological, -> { order(created_at: :asc) }
  end
end
