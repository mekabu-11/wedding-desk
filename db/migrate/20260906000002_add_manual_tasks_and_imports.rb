class AddManualTasksAndImports < ActiveRecord::Migration[8.1]
  def change
    change_column_null :tasks, :candidate_id, true
    add_column :tasks, :origin, :string, null: false, default: "ai"
    add_column :tasks, :starts_on, :date
    add_column :tasks, :source_key, :string
    add_column :tasks, :source_details, :text
    add_index :tasks, [:wedding_id, :source_key], unique: true
    add_check_constraint :tasks, "origin IN ('ai', 'manual', 'import')", name: "tasks_valid_origin"
    add_check_constraint :tasks, "origin != 'ai' OR candidate_id IS NOT NULL", name: "ai_tasks_require_candidate"
    add_check_constraint :tasks, "origin != 'import' OR source_key IS NOT NULL", name: "import_tasks_require_source"
    create_table :task_imports do |t|
      t.references :wedding, null: false, foreign_key: true
      t.string :digest, null: false
      t.text :rows, null: false
      t.string :status, null: false, default: "pending"
      t.integer :imported_count
      t.integer :skipped_count
      t.datetime :committed_at
      t.timestamps
    end
    add_index :task_imports, [:wedding_id, :digest], unique: true
    add_check_constraint :task_imports, "status IN ('pending', 'committed')", name: "task_imports_valid_status"
  end
end
