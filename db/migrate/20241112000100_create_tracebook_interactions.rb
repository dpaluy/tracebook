# frozen_string_literal: true

class CreateTracebookInteractions < ActiveRecord::Migration[8.0]
  def change
    create_table :tracebook_interactions do |t|
      t.string :project
      t.string :provider, null: false
      t.string :model, null: false
      t.string :session_id

      t.text :request_payload
      t.text :response_payload
      t.text :request_text
      t.text :response_text

      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :total_tokens
      t.integer :latency_ms

      t.integer :status, null: false, default: 0
      t.integer :review_state, null: false, default: 0
      t.string :error_class
      t.text :error_message

      t.string :trackable_type
      t.bigint :trackable_id
      t.bigint :parent_id

      t.text :tags
      t.text :metadata

      t.string :request_payload_store, null: false, default: "inline"
      t.string :response_payload_store, null: false, default: "inline"
      t.bigint :request_payload_blob_id
      t.bigint :response_payload_blob_id

      t.integer :cost_input_cents, default: 0, null: false
      t.integer :cost_output_cents, default: 0, null: false
      t.integer :cost_total_cents, default: 0, null: false
      t.string :currency, null: false, default: "USD"

      t.timestamps
    end

    add_index :tracebook_interactions, :created_at
    add_index :tracebook_interactions, [ :provider, :model, :created_at ]
    add_index :tracebook_interactions, [ :project, :created_at ]
    add_index :tracebook_interactions, :session_id
    add_index :tracebook_interactions, :status
    add_index :tracebook_interactions, :review_state
    add_index :tracebook_interactions, :parent_id
    add_index :tracebook_interactions, [ :trackable_type, :trackable_id ]
  end
end
