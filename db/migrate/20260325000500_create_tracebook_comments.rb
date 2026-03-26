# frozen_string_literal: true

class CreateTracebookComments < ActiveRecord::Migration[8.0]
  def change
    create_table :tracebook_comments do |t|
      t.references :chat_review, null: false, foreign_key: { to_table: :tracebook_chat_reviews }
      t.string :author, null: false
      t.text :body, null: false

      t.timestamps
    end

    add_index :tracebook_comments, [ :chat_review_id, :created_at ]
  end
end
