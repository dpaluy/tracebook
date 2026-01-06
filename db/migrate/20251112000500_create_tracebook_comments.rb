# frozen_string_literal: true

class CreateTracebookComments < ActiveRecord::Migration[8.0]
  def change
    create_table :tracebook_comments do |t|
      t.references :interaction, null: false, foreign_key: { to_table: :tracebook_interactions }
      t.string :author, null: false
      t.text :body, null: false

      t.timestamps
    end

    add_index :tracebook_comments, [ :interaction_id, :created_at ]
  end
end
