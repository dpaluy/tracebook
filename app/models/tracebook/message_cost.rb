# frozen_string_literal: true

module Tracebook
  class MessageCost < ApplicationRecord
    self.table_name = "tracebook_message_costs"

    belongs_to :message, polymorphic: true, optional: true

    validates :message_type, presence: true
    validates :message_id, presence: true
  end
end
