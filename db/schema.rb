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

ActiveRecord::Schema[8.1].define(version: 2026_09_07_000001) do
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
    t.check_constraint "review_status::text = ANY (ARRAY['pending'::character varying::text, 'accepted'::character varying::text, 'rejected'::character varying::text])", name: "candidates_valid_status"
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

  create_table "memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "role", default: "editor", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.bigint "wedding_id", null: false
    t.index ["user_id"], name: "index_memberships_on_user_id", unique: true
    t.index ["wedding_id", "user_id"], name: "index_memberships_on_wedding_id_and_user_id", unique: true
    t.index ["wedding_id"], name: "index_memberships_on_wedding_id"
    t.check_constraint "role::text = ANY (ARRAY['owner'::character varying, 'editor'::character varying]::text[])", name: "memberships_valid_role"
  end

  create_table "solid_queue_batch_executions", force: :cascade do |t|
    t.bigint "batch_id", null: false
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.index ["batch_id"], name: "index_solid_queue_batch_executions_on_batch_id"
    t.index ["job_id"], name: "index_solid_queue_batch_executions_on_job_id", unique: true
  end

  create_table "solid_queue_batches", force: :cascade do |t|
    t.string "active_job_batch_id"
    t.integer "completed_jobs", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.datetime "enqueued_at"
    t.datetime "failed_at"
    t.integer "failed_jobs", default: 0, null: false
    t.datetime "finished_at"
    t.text "metadata"
    t.text "on_failure"
    t.text "on_finish"
    t.text "on_success"
    t.integer "total_jobs", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_batch_id"], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
    t.index ["finished_at"], name: "index_solid_queue_batches_on_finished_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.bigint "batch_id"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["batch_id"], name: "index_solid_queue_jobs_on_batch_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_on_scheduled_at_and_finished_at"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.datetime "updated_at", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority"
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "task_imports", force: :cascade do |t|
    t.datetime "committed_at"
    t.datetime "created_at", null: false
    t.string "digest", null: false
    t.integer "imported_count"
    t.text "rows", null: false
    t.integer "skipped_count"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "wedding_id", null: false
    t.index ["wedding_id", "digest"], name: "index_task_imports_on_wedding_id_and_digest", unique: true
    t.index ["wedding_id"], name: "index_task_imports_on_wedding_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'committed'::character varying]::text[])", name: "task_imports_valid_status"
  end

  create_table "tasks", force: :cascade do |t|
    t.string "assignee", default: "unknown", null: false
    t.bigint "candidate_id"
    t.string "category", default: "other", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "due_at"
    t.date "due_on"
    t.integer "lock_version", default: 0, null: false
    t.string "origin", default: "ai", null: false
    t.text "original_due_text"
    t.text "source_details"
    t.string "source_key"
    t.date "starts_on"
    t.string "status", default: "todo", null: false
    t.text "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "wedding_id", null: false
    t.index ["candidate_id"], name: "index_tasks_on_candidate_id", unique: true
    t.index ["wedding_id", "source_key"], name: "index_tasks_on_wedding_id_and_source_key", unique: true
    t.index ["wedding_id", "status", "due_on"], name: "index_tasks_on_wedding_id_and_status_and_due_on"
    t.index ["wedding_id"], name: "index_tasks_on_wedding_id"
    t.check_constraint "origin::text <> 'import'::text OR source_key IS NOT NULL", name: "import_tasks_require_source"
    t.check_constraint "origin::text = ANY (ARRAY['ai'::character varying, 'manual'::character varying, 'import'::character varying]::text[])", name: "tasks_valid_origin"
    t.check_constraint "status::text = ANY (ARRAY['todo'::character varying::text, 'doing'::character varying::text, 'done'::character varying::text, 'cancelled'::character varying::text])", name: "tasks_valid_status"
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
    t.string "venue_name"
    t.date "wedding_date"
  end

  add_foreign_key "analysis_runs", "documents"
  add_foreign_key "candidates", "analysis_runs"
  add_foreign_key "candidates", "documents"
  add_foreign_key "documents", "weddings"
  add_foreign_key "memberships", "users"
  add_foreign_key "memberships", "weddings"
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "task_imports", "weddings"
  add_foreign_key "tasks", "candidates"
  add_foreign_key "tasks", "weddings"
end
