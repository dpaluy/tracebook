# frozen_string_literal: true

class CreateTracebookRedactionRules < ActiveRecord::Migration[8.0]
  def change
    create_table :tracebook_redaction_rules do |t|
      t.string :name, null: false
      t.text :pattern, null: false
      t.string :replacement, null: false, default: "[REDACTED]"
      t.integer :applies_to, null: false, default: 2
      t.boolean :enabled, null: false, default: true
      t.integer :priority, null: false, default: 100

      t.timestamps
    end

    add_index :tracebook_redaction_rules, :enabled
    add_index :tracebook_redaction_rules, :priority
  end
end
