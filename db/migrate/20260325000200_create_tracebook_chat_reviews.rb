# frozen_string_literal: true

class CreateTracebookChatReviews < ActiveRecord::Migration[8.0]
  def change
    create_table :tracebook_chat_reviews do |t|
      t.string :chat_type, null: false
      t.bigint :chat_id, null: false
      t.integer :review_state, null: false, default: 0
      t.text :review_comment
      t.datetime :reviewed_at
      t.string :reviewed_by

      t.timestamps
    end

    add_index :tracebook_chat_reviews, [ :chat_type, :chat_id ], unique: true, name: "index_tracebook_chat_reviews_on_chat"
    add_index :tracebook_chat_reviews, :review_state
  end
end
