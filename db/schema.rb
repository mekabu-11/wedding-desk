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

ActiveRecord::Schema[8.1].define(version: 2026_09_08_000008) do
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

  create_table "budget_items", force: :cascade do |t|
    t.bigint "amount_yen"
    t.string "calculation_mode", default: "manual", null: false
    t.string "category", default: "other", null: false
    t.string "certainty", default: "estimate", null: false
    t.datetime "created_at", null: false
    t.string "direction", null: false
    t.string "inclusion", default: "included", null: false
    t.integer "lock_version", default: 0, null: false
    t.integer "manual_quantity"
    t.string "quantity_basis"
    t.string "rounding", default: "floor", null: false
    t.bigint "source_id"
    t.string "source_kind", default: "manual", null: false
    t.string "tax_basis", default: "unknown", null: false
    t.decimal "tax_rate", precision: 5, scale: 2
    t.text "title", null: false
    t.bigint "unit_price"
    t.datetime "updated_at", null: false
    t.bigint "wedding_id", null: false
    t.index ["wedding_id", "direction", "inclusion"], name: "index_budget_items_on_wedding_id_and_direction_and_inclusion"
    t.index ["wedding_id", "source_kind", "source_id"], name: "index_budget_items_on_wedding_and_source", unique: true, where: "(((source_kind)::text <> 'manual'::text) AND (source_id IS NOT NULL))"
    t.index ["wedding_id"], name: "index_budget_items_on_wedding_id"
    t.check_constraint "amount_yen IS NULL OR amount_yen >= 0", name: "budget_items_amount_non_negative"
    t.check_constraint "source_kind::text = 'manual'::text OR source_id IS NOT NULL", name: "budget_items_source_required"
    t.check_constraint "tax_basis::text <> 'exclusive'::text OR calculation_mode::text <> 'quantity'::text OR tax_rate IS NOT NULL", name: "budget_items_exclusive_tax_rate_required"
    t.check_constraint "tax_rate IS NULL OR tax_rate >= 0::numeric AND tax_rate <= 100::numeric", name: "budget_items_tax_rate_range"
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

  create_table "cash_gift_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "default_amount_yen", null: false
    t.string "label", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "wedding_id", null: false
    t.index ["wedding_id", "label"], name: "index_cash_gift_rules_on_wedding_id_and_label", unique: true
    t.index ["wedding_id"], name: "index_cash_gift_rules_on_wedding_id"
    t.check_constraint "default_amount_yen >= 0", name: "cash_gift_rules_amount_non_negative"
  end

  create_table "change_events", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id"
    t.text "after"
    t.text "before"
    t.datetime "created_at", null: false
    t.text "source"
    t.bigint "target_id", null: false
    t.string "target_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "wedding_id", null: false
    t.index ["actor_id"], name: "index_change_events_on_actor_id"
    t.index ["wedding_id", "created_at"], name: "index_change_events_on_wedding_id_and_created_at"
    t.index ["wedding_id", "target_type", "target_id", "created_at"], name: "index_change_events_on_target"
    t.index ["wedding_id"], name: "index_change_events_on_wedding_id"
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

  create_table "gift_assignments", force: :cascade do |t|
    t.bigint "budget_item_id"
    t.datetime "created_at", null: false
    t.bigint "gift_set_id", null: false
    t.bigint "household_id", null: false
    t.boolean "included", default: true, null: false
    t.integer "lock_version", default: 0, null: false
    t.text "notes"
    t.integer "quantity", default: 1, null: false
    t.datetime "updated_at", null: false
    t.bigint "wedding_id", null: false
    t.index ["budget_item_id"], name: "index_gift_assignments_on_budget_item_id", unique: true, where: "(budget_item_id IS NOT NULL)"
    t.index ["gift_set_id"], name: "index_gift_assignments_on_gift_set_id"
    t.index ["household_id"], name: "index_gift_assignments_on_household_id"
    t.index ["wedding_id", "household_id"], name: "index_gift_assignments_on_wedding_id_and_household_id", unique: true
    t.index ["wedding_id"], name: "index_gift_assignments_on_wedding_id"
    t.check_constraint "quantity > 0", name: "gift_assignments_quantity_positive"
  end

  create_table "gift_set_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "gift_set_id", null: false
    t.string "kind", default: "other", null: false
    t.integer "lock_version", default: 0, null: false
    t.string "name", null: false
    t.string "rounding", default: "floor", null: false
    t.string "tax_basis", default: "unknown", null: false
    t.decimal "tax_rate", precision: 5, scale: 2
    t.bigint "unit_price_yen", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["gift_set_id"], name: "index_gift_set_items_on_gift_set_id"
    t.check_constraint "rounding::text = ANY (ARRAY['floor'::character varying::text, 'round'::character varying::text, 'ceil'::character varying::text])", name: "gift_set_items_valid_rounding"
    t.check_constraint "tax_basis::text <> 'exclusive'::text OR tax_rate IS NOT NULL", name: "gift_set_items_exclusive_tax_rate_required"
    t.check_constraint "tax_rate IS NULL OR tax_rate >= 0::numeric AND tax_rate <= 100::numeric", name: "gift_set_items_tax_rate_range"
  end

  create_table "gift_sets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.string "name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.bigint "wedding_id", null: false
    t.index ["wedding_id", "name"], name: "index_gift_sets_on_wedding_id_and_name", unique: true
    t.index ["wedding_id"], name: "index_gift_sets_on_wedding_id"
  end

  create_table "guests", force: :cascade do |t|
    t.string "age_group", default: "adult", null: false
    t.text "allergies"
    t.string "attendance", default: "unanswered", null: false
    t.datetime "created_at", null: false
    t.string "gender"
    t.bigint "household_id"
    t.string "invitation_status"
    t.integer "lock_version", default: 0, null: false
    t.text "name", null: false
    t.text "notes"
    t.text "relationship"
    t.text "roles"
    t.bigint "seating_table_id"
    t.string "side", default: "unknown", null: false
    t.datetime "updated_at", null: false
    t.bigint "wedding_id", null: false
    t.index ["household_id"], name: "index_guests_on_household_id"
    t.index ["seating_table_id"], name: "index_guests_on_seating_table_id"
    t.index ["wedding_id", "attendance"], name: "index_guests_on_wedding_id_and_attendance"
    t.index ["wedding_id", "household_id"], name: "index_guests_on_wedding_id_and_household_id"
    t.index ["wedding_id"], name: "index_guests_on_wedding_id"
  end

  create_table "households", force: :cascade do |t|
    t.boolean "archived", default: false, null: false
    t.bigint "cash_gift_rule_id"
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.text "name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.bigint "wedding_id", null: false
    t.index ["cash_gift_rule_id"], name: "index_households_on_cash_gift_rule_id"
    t.index ["wedding_id", "code"], name: "index_households_on_wedding_id_and_code", unique: true
    t.index ["wedding_id"], name: "index_households_on_wedding_id"
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
    t.check_constraint "role::text = ANY (ARRAY['owner'::character varying::text, 'editor'::character varying::text])", name: "memberships_valid_role"
  end

  create_table "money_movements", force: :cascade do |t|
    t.bigint "amount_yen", null: false
    t.bigint "budget_item_id", null: false
    t.datetime "created_at", null: false
    t.string "idempotency_key"
    t.string "kind", null: false
    t.integer "lock_version", default: 0, null: false
    t.text "note"
    t.date "occurred_on", null: false
    t.datetime "updated_at", null: false
    t.bigint "wedding_id", null: false
    t.index ["budget_item_id"], name: "index_money_movements_on_budget_item_id"
    t.index ["wedding_id", "budget_item_id", "occurred_on"], name: "idx_on_wedding_id_budget_item_id_occurred_on_f7b7f90557"
    t.index ["wedding_id", "idempotency_key"], name: "index_money_movements_on_wedding_id_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["wedding_id"], name: "index_money_movements_on_wedding_id"
    t.check_constraint "amount_yen > 0", name: "money_movements_amount_positive"
  end

  create_table "music_details", force: :cascade do |t|
    t.text "artist"
    t.datetime "created_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.text "original_text"
    t.bigint "planning_option_id", null: false
    t.string "scene"
    t.text "selected_track"
    t.integer "start_offset_seconds"
    t.datetime "updated_at", null: false
    t.bigint "wedding_id", null: false
    t.text "wish_track_a"
    t.text "wish_track_b"
    t.index ["planning_option_id"], name: "index_music_details_on_planning_option_id", unique: true
    t.index ["wedding_id"], name: "index_music_details_on_wedding_id"
    t.check_constraint "start_offset_seconds IS NULL OR start_offset_seconds >= 0", name: "music_details_offset_non_negative"
  end

  create_table "planning_cost_links", force: :cascade do |t|
    t.bigint "budget_item_id", null: false
    t.datetime "created_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.bigint "planning_item_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "wedding_id", null: false
    t.index ["budget_item_id"], name: "index_planning_cost_links_on_budget_item_id"
    t.index ["planning_item_id"], name: "index_planning_cost_links_on_planning_item_id"
    t.index ["wedding_id", "planning_item_id", "budget_item_id"], name: "index_planning_cost_links_unique_pair", unique: true
    t.index ["wedding_id", "planning_item_id"], name: "index_planning_cost_links_on_wedding_id_and_planning_item_id"
    t.index ["wedding_id"], name: "index_planning_cost_links_on_wedding_id"
  end

  create_table "planning_items", force: :cascade do |t|
    t.string "category", default: "other", null: false
    t.datetime "created_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.text "notes"
    t.integer "position", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "wedding_id", null: false
    t.index ["wedding_id", "category", "position", "id"], name: "idx_on_wedding_id_category_position_id_fdd25119f0"
    t.index ["wedding_id"], name: "index_planning_items_on_wedding_id"
  end

  create_table "planning_options", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "lock_version", default: 0, null: false
    t.bigint "planning_item_id", null: false
    t.bigint "reference_price_yen"
    t.string "status", default: "draft", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "wedding_id", null: false
    t.index ["planning_item_id"], name: "index_planning_options_on_planning_item_id"
    t.index ["planning_item_id"], name: "index_planning_options_one_selected_per_item", unique: true, where: "((status)::text = 'selected'::text)"
    t.index ["wedding_id", "planning_item_id", "id"], name: "idx_on_wedding_id_planning_item_id_id_a157950c23"
    t.index ["wedding_id"], name: "index_planning_options_on_wedding_id"
    t.check_constraint "reference_price_yen IS NULL OR reference_price_yen >= 0", name: "planning_options_reference_price_non_negative"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying::text, 'considering'::character varying::text, 'selected'::character varying::text, 'rejected'::character varying::text])", name: "planning_options_valid_status"
  end

  create_table "seating_tables", force: :cascade do |t|
    t.integer "capacity"
    t.datetime "created_at", null: false
    t.string "label", null: false
    t.integer "lock_version", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "wedding_id", null: false
    t.index ["wedding_id", "label"], name: "index_seating_tables_on_wedding_id_and_label", unique: true
    t.index ["wedding_id"], name: "index_seating_tables_on_wedding_id"
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
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'committed'::character varying::text])", name: "task_imports_valid_status"
  end

  create_table "task_planning_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.bigint "planning_item_id", null: false
    t.bigint "task_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "wedding_id", null: false
    t.index ["planning_item_id"], name: "index_task_planning_links_on_planning_item_id"
    t.index ["task_id"], name: "index_task_planning_links_on_task_id"
    t.index ["wedding_id", "planning_item_id"], name: "index_task_planning_links_on_wedding_id_and_planning_item_id"
    t.index ["wedding_id", "task_id", "planning_item_id"], name: "index_task_planning_links_unique_pair", unique: true
    t.index ["wedding_id"], name: "index_task_planning_links_on_wedding_id"
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
    t.check_constraint "assignee::text = ANY (ARRAY['person_a'::character varying::text, 'person_b'::character varying::text, 'both'::character varying::text, 'unknown'::character varying::text])", name: "tasks_valid_assignee"
    t.check_constraint "origin::text <> 'import'::text OR source_key IS NOT NULL", name: "import_tasks_require_source"
    t.check_constraint "origin::text = ANY (ARRAY['ai'::character varying::text, 'manual'::character varying::text, 'import'::character varying::text])", name: "tasks_valid_origin"
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
  add_foreign_key "budget_items", "weddings"
  add_foreign_key "candidates", "analysis_runs"
  add_foreign_key "candidates", "documents"
  add_foreign_key "cash_gift_rules", "weddings"
  add_foreign_key "change_events", "users", column: "actor_id"
  add_foreign_key "change_events", "weddings"
  add_foreign_key "documents", "weddings"
  add_foreign_key "gift_assignments", "budget_items"
  add_foreign_key "gift_assignments", "gift_sets"
  add_foreign_key "gift_assignments", "households"
  add_foreign_key "gift_assignments", "weddings"
  add_foreign_key "gift_set_items", "gift_sets"
  add_foreign_key "gift_sets", "weddings"
  add_foreign_key "guests", "households"
  add_foreign_key "guests", "seating_tables"
  add_foreign_key "guests", "weddings"
  add_foreign_key "households", "cash_gift_rules"
  add_foreign_key "households", "weddings"
  add_foreign_key "memberships", "users"
  add_foreign_key "memberships", "weddings"
  add_foreign_key "money_movements", "budget_items"
  add_foreign_key "money_movements", "weddings"
  add_foreign_key "music_details", "planning_options"
  add_foreign_key "music_details", "weddings"
  add_foreign_key "planning_cost_links", "budget_items"
  add_foreign_key "planning_cost_links", "planning_items"
  add_foreign_key "planning_cost_links", "weddings"
  add_foreign_key "planning_items", "weddings"
  add_foreign_key "planning_options", "planning_items"
  add_foreign_key "planning_options", "weddings"
  add_foreign_key "seating_tables", "weddings"
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "task_imports", "weddings"
  add_foreign_key "task_planning_links", "planning_items"
  add_foreign_key "task_planning_links", "tasks"
  add_foreign_key "task_planning_links", "weddings"
  add_foreign_key "tasks", "candidates"
  add_foreign_key "tasks", "weddings"
end
