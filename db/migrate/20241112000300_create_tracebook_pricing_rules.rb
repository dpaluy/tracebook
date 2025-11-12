# frozen_string_literal: true

class CreateTracebookPricingRules < ActiveRecord::Migration[8.0]
  def change
    create_table :tracebook_pricing_rules do |t|
      t.string :provider, null: false
      t.string :model_glob, null: false
      t.string :unit, null: false, default: "per_1k_tokens"
      t.integer :input_cents_per_unit, null: false, default: 0
      t.integer :output_cents_per_unit, null: false, default: 0
      t.date :effective_from, null: false
      t.date :effective_to
      t.string :currency, null: false, default: "USD"

      t.timestamps
    end

    add_index :tracebook_pricing_rules, :provider
    add_index :tracebook_pricing_rules, [ :provider, :effective_from ], name: "index_tracebook_pricing_on_provider_effective_from"
  end
end
