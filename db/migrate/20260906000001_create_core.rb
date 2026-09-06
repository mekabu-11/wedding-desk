class CreateCore < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.timestamps
    end
    add_index :users, :email, unique: true
    create_table :weddings do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :name, null: false
      t.date :wedding_date
      t.string :venue_name
      t.string :self_name
      t.string :partner_name
      t.bigint :budget_yen
      t.timestamps
    end
    create_table :documents do |t|
      t.references :wedding, null: false, foreign_key: true
      t.string :title, null: false
      t.text :original_text, null: false
      t.string :source_type, null: false
      t.string :direction, null: false, default: "unknown"
      t.datetime :occurred_at
      t.string :content_hash, null: false
      t.boolean :sample, null: false, default: false
      t.timestamps
    end
    add_index :documents, [:wedding_id, :content_hash], unique: true
    create_table :analysis_runs do |t|
      t.references :document, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :provider, null: false
      t.string :model_version
      t.string :prompt_version, null: false, default: "tasks-v1"
      t.string :schema_version, null: false, default: "tasks-v1"
      t.text :summary
      t.string :category
      t.string :error_code
      t.integer :attempt, null: false, default: 0
      t.string :attempt_token
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    create_table :candidates do |t|
      t.references :document, null: false, foreign_key: true
      t.references :analysis_run, null: false, foreign_key: true
      t.text :payload, null: false
      t.text :evidence, null: false
      t.string :fingerprint, null: false
      t.string :review_status, null: false, default: "pending"
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :candidates, [:document_id, :fingerprint], unique: true
    create_table :tasks do |t|
      t.references :wedding, null: false, foreign_key: true
      t.references :candidate, null: false, foreign_key: true, index: { unique: true }
      t.text :title, null: false
      t.text :description
      t.string :assignee, null: false, default: "unknown"
      t.date :due_on
      t.datetime :due_at
      t.text :original_due_text
      t.string :category, null: false, default: "other"
      t.string :status, null: false, default: "todo"
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :tasks, [:wedding_id, :status, :due_on]
    add_check_constraint :tasks, "status IN ('todo','doing','done','cancelled')", name: "tasks_valid_status"
    add_check_constraint :candidates, "review_status IN ('pending','accepted','rejected')", name: "candidates_valid_status"
  end
end
