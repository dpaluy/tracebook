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

ActiveRecord::Schema[8.1].define(version: 2026_03_25_000500) do
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

  create_table "tracebook_chat_reviews", force: :cascade do |t|
    t.bigint "chat_id", null: false
    t.string "chat_type", null: false
    t.datetime "created_at", null: false
    t.text "review_comment"
    t.integer "review_state", default: 0, null: false
    t.datetime "reviewed_at"
    t.string "reviewed_by"
    t.datetime "updated_at", null: false
    t.index ["chat_type", "chat_id"], name: "index_tracebook_chat_reviews_on_chat", unique: true
    t.index ["review_state"], name: "index_tracebook_chat_reviews_on_review_state"
  end

  create_table "tracebook_comments", force: :cascade do |t|
    t.string "author", null: false
    t.text "body", null: false
    t.integer "chat_review_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_review_id", "created_at"], name: "index_tracebook_comments_on_chat_review_id_and_created_at"
    t.index ["chat_review_id"], name: "index_tracebook_comments_on_chat_review_id"
  end

  create_table "tracebook_message_costs", force: :cascade do |t|
    t.decimal "cost_input_cents", precision: 12, scale: 4, default: "0.0", null: false
    t.decimal "cost_output_cents", precision: 12, scale: 4, default: "0.0", null: false
    t.decimal "cost_total_cents", precision: 12, scale: 4, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.integer "latency_ms"
    t.bigint "message_id", null: false
    t.string "message_type", null: false
    t.datetime "updated_at", null: false
    t.index ["message_type", "message_id"], name: "index_tracebook_message_costs_on_message", unique: true
  end

  create_table "tracebook_pricing_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.date "effective_from", null: false
    t.date "effective_to"
    t.decimal "input_cents_per_unit", precision: 10, scale: 4, default: "0.0", null: false
    t.string "model_glob", null: false
    t.decimal "output_cents_per_unit", precision: 10, scale: 4, default: "0.0", null: false
    t.string "provider", null: false
    t.string "unit", default: "per_1m_tokens", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "effective_from"], name: "index_tracebook_pricing_on_provider_effective_from"
    t.index ["provider"], name: "index_tracebook_pricing_rules_on_provider"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "tracebook_comments", "tracebook_chat_reviews", column: "chat_review_id"
end
