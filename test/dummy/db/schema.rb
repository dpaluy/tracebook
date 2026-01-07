# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_07_000100) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "tracebook_comments", force: :cascade do |t|
    t.string "author", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "interaction_id", null: false
    t.datetime "updated_at", null: false
    t.index ["interaction_id", "created_at"], name: "index_tracebook_comments_on_interaction_id_and_created_at"
    t.index ["interaction_id"], name: "index_tracebook_comments_on_interaction_id"
  end

  create_table "tracebook_interactions", force: :cascade do |t|
    t.bigint "actor_id"
    t.string "actor_type"
    t.integer "cost_input_cents", default: 0, null: false
    t.integer "cost_output_cents", default: 0, null: false
    t.integer "cost_total_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.string "error_class"
    t.text "error_message"
    t.integer "input_tokens"
    t.integer "latency_ms"
    t.text "metadata"
    t.string "model", null: false
    t.integer "output_tokens"
    t.bigint "parent_id"
    t.string "project"
    t.string "provider", null: false
    t.text "redaction_audit"
    t.text "request_payload"
    t.bigint "request_payload_blob_id"
    t.string "request_payload_store", default: "inline", null: false
    t.text "request_text"
    t.text "response_payload"
    t.bigint "response_payload_blob_id"
    t.string "response_payload_store", default: "inline", null: false
    t.text "response_text"
    t.text "review_comment"
    t.integer "review_state", default: 0, null: false
    t.datetime "reviewed_at"
    t.string "reviewed_by"
    t.string "session_id"
    t.integer "status", default: 0, null: false
    t.text "tags"
    t.integer "total_tokens"
    t.datetime "updated_at", null: false
    t.index ["actor_type", "actor_id"], name: "index_tracebook_interactions_on_actor_type_and_actor_id"
    t.index ["created_at"], name: "index_tracebook_interactions_on_created_at"
    t.index ["parent_id"], name: "index_tracebook_interactions_on_parent_id"
    t.index ["project", "created_at"], name: "index_tracebook_interactions_on_project_and_created_at"
    t.index ["provider", "model", "created_at"], name: "idx_on_provider_model_created_at_a4ddbef83a"
    t.index ["review_state"], name: "index_tracebook_interactions_on_review_state"
    t.index ["session_id"], name: "index_tracebook_interactions_on_session_id"
    t.index ["status"], name: "index_tracebook_interactions_on_status"
  end

  create_table "tracebook_pricing_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.date "effective_from", null: false
    t.date "effective_to"
    t.integer "input_cents_per_unit", default: 0, null: false
    t.string "model_glob", null: false
    t.integer "output_cents_per_unit", default: 0, null: false
    t.string "provider", null: false
    t.string "unit", default: "per_1k_tokens", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "effective_from"], name: "index_tracebook_pricing_on_provider_effective_from"
    t.index ["provider"], name: "index_tracebook_pricing_rules_on_provider"
  end

  create_table "tracebook_rollups_dailies", force: :cascade do |t|
    t.integer "cost_cents_sum", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.date "date", null: false
    t.integer "error_count", default: 0, null: false
    t.integer "input_tokens_sum", default: 0, null: false
    t.integer "interactions_count", default: 0, null: false
    t.string "model"
    t.integer "output_tokens_sum", default: 0, null: false
    t.string "project"
    t.string "provider"
    t.integer "success_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["date", "project", "provider", "model"], name: "index_tracebook_rollups_on_dimensions", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "tracebook_comments", "tracebook_interactions", column: "interaction_id"
end
