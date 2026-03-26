# frozen_string_literal: true

class CreateTracebookMessageCosts < ActiveRecord::Migration[8.0]
  def change
    create_table :tracebook_message_costs do |t|
      t.string :message_type, null: false
      t.bigint :message_id, null: false
      t.decimal :cost_input_cents, precision: 12, scale: 4, default: 0, null: false
      t.decimal :cost_output_cents, precision: 12, scale: 4, default: 0, null: false
      t.decimal :cost_total_cents, precision: 12, scale: 4, default: 0, null: false
      t.string :currency, null: false, default: "USD"
      t.integer :latency_ms

      t.timestamps
    end

    add_index :tracebook_message_costs, [ :message_type, :message_id ], unique: true, name: "index_tracebook_message_costs_on_message"
  end
end
