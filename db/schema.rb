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

ActiveRecord::Schema[8.1].define(version: 2026_09_06_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "analysis_runs", force: :cascade do |t|
    t.integer "attempt", default: 0, null: false
    t.string "attempt_token"
    t.string "category"
    t.datetime "created_at", null: false
    t.bigint "document_id", null: false
    t.string "error_code"
    t.datetime "finished_at"
    t.string "model_version"
    t.string "prompt_version", default: "tasks-v1", null: false
    t.string "provider", null: false
    t.string "schema_version", default: "tasks-v1", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.text "summary"
    t.datetime "updated_at", null: false
    t.index ["document_id"], name: "index_analysis_runs_on_document_id"
  end

  create_table "candidates", force: :cascade do |t|
    t.bigint "analysis_run_id", null: false
    t.datetime "created_at", null: false
    t.bigint "document_id", null: false
    t.text "evidence", null: false
    t.string "fingerprint", null: false
    t.text "payload", null: false
    t.string "review_status", default: "pending", null: false
    t.datetime "reviewed_at"
    t.datetime "updated_at", null: false
    t.index ["analysis_run_id"], name: "index_candidates_on_analysis_run_id"
    t.index ["document_id", "fingerprint"], name: "index_candidates_on_document_id_and_fingerprint", unique: true
    t.index ["document_id"], name: "index_candidates_on_document_id"
    t.check_constraint "review_status::text = ANY (ARRAY['pending'::character varying, 'accepted'::character varying, 'rejected'::character varying]::text[])", name: "candidates_valid_status"
  end

  create_table "documents", force: :cascade do |t|
    t.string "content_hash", null: false
    t.datetime "created_at", null: false
    t.string "direction", default: "unknown", null: false
    t.datetime "occurred_at"
    t.text "original_text", null: false
    t.boolean "sample", default: false, null: false
    t.string "source_type", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "wedding_id", null: false
    t.index ["wedding_id", "content_hash"], name: "index_documents_on_wedding_id_and_content_hash", unique: true
    t.index ["wedding_id"], name: "index_documents_on_wedding_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.string "assignee", default: "unknown", null: false
    t.bigint "candidate_id", null: false
    t.string "category", default: "other", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "due_at"
    t.date "due_on"
    t.integer "lock_version", default: 0, null: false
    t.text "original_due_text"
    t.string "status", default: "todo", null: false
    t.text "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "wedding_id", null: false
    t.index ["candidate_id"], name: "index_tasks_on_candidate_id", unique: true
    t.index ["wedding_id", "status", "due_on"], name: "index_tasks_on_wedding_id_and_status_and_due_on"
    t.index ["wedding_id"], name: "index_tasks_on_wedding_id"
    t.check_constraint "status::text = ANY (ARRAY['todo'::character varying, 'doing'::character varying, 'done'::character varying, 'cancelled'::character varying]::text[])", name: "tasks_valid_status"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "weddings", force: :cascade do |t|
    t.bigint "budget_yen"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "partner_name"
    t.string "self_name"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "venue_name"
    t.date "wedding_date"
    t.index ["user_id"], name: "index_weddings_on_user_id", unique: true
  end

  add_foreign_key "analysis_runs", "documents"
  add_foreign_key "candidates", "analysis_runs"
  add_foreign_key "candidates", "documents"
  add_foreign_key "documents", "weddings"
  add_foreign_key "tasks", "candidates"
  add_foreign_key "tasks", "weddings"
  add_foreign_key "weddings", "users"
end
