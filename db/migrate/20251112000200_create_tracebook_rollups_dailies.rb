# frozen_string_literal: true

class CreateTracebookRollupsDailies < ActiveRecord::Migration[8.0]
  def change
    create_table :tracebook_rollups_dailies do |t|
      t.date :date, null: false
      t.string :project
      t.string :provider
      t.string :model

      t.integer :interactions_count, null: false, default: 0
      t.integer :success_count, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      t.integer :input_tokens_sum, null: false, default: 0
      t.integer :output_tokens_sum, null: false, default: 0
      t.integer :cost_cents_sum, null: false, default: 0
      t.string :currency, null: false, default: "USD"

      t.timestamps
    end

    add_index :tracebook_rollups_dailies, [ :date, :project, :provider, :model ], unique: true, name: "index_tracebook_rollups_on_dimensions"
  end
end
