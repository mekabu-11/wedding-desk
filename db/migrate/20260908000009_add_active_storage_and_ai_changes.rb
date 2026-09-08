class AddActiveStorageAndAiChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :active_storage_blobs do |t|
      t.string :key, null: false
      t.string :filename, null: false
      t.string :content_type
      t.text :metadata
      t.string :service_name, null: false
      t.bigint :byte_size, null: false
      t.string :checksum
      t.datetime :created_at, null: false
    end
    add_index :active_storage_blobs, :key, unique: true

    create_table :active_storage_attachments do |t|
      t.string :name, null: false
      t.references :record, polymorphic: true, null: false, index: false
      t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.datetime :created_at, null: false
    end
    add_index :active_storage_attachments, [:record_type, :record_id, :name, :blob_id],
      unique: true, name: "index_active_storage_attachments_uniqueness"

    create_table :active_storage_variant_records do |t|
      t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.string :variation_digest, null: false
      t.index [:blob_id, :variation_digest], unique: true
    end

    change_column_null :documents, :original_text, true
    add_column :documents, :memo, :text
    add_index :documents, [:wedding_id, :created_at]

    create_table :source_links do |t|
      t.references :wedding, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: true
      t.string :target_type, null: false
      t.bigint :target_id, null: false
      t.bigint :attachment_id
      t.integer :page
      t.text :quote
      t.text :region
      t.timestamps
    end
    add_index :source_links, [:wedding_id, :target_type, :target_id], name: "index_source_links_on_target"
    add_foreign_key :source_links, :active_storage_attachments, column: :attachment_id
    add_index :source_links, [:document_id, :target_type, :target_id], name: "index_source_links_on_document_target"

    create_table :change_sets do |t|
      t.references :wedding, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :state, null: false, default: "pending"
      t.string :operation_key, null: false
      t.text :summary
      t.text :error
      t.timestamps
    end
    add_index :change_sets, [:wedding_id, :operation_key], unique: true
    add_check_constraint :change_sets, "state IN ('pending','applied','failed')", name: "change_sets_valid_state"

    create_table :change_operations do |t|
      t.references :change_set, null: false, foreign_key: true
      t.string :operation_key, null: false
      t.string :action, null: false
      t.string :entity_type, null: false
      t.bigint :target_id
      t.integer :expected_lock_version
      t.text :attributes_data
      t.text :before_data
      t.text :after_data
      t.text :evidence_data
      t.text :uncertainties_data
      t.text :depends_on_data
      t.string :state, null: false, default: "pending"
      t.text :error
      t.timestamps
    end
    add_index :change_operations, [:change_set_id, :operation_key], unique: true
    add_check_constraint :change_operations, "action IN ('create','update','link')", name: "change_operations_valid_action"
    add_check_constraint :change_operations, "state IN ('pending','applied','failed')", name: "change_operations_valid_state"

    execute <<~SQL
      INSERT INTO source_links (wedding_id, document_id, target_type, target_id, created_at, updated_at)
      SELECT tasks.wedding_id, candidates.document_id, 'Task', tasks.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM tasks
      INNER JOIN candidates ON candidates.id = tasks.candidate_id
      WHERE tasks.candidate_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM source_links existing
          WHERE existing.document_id = candidates.document_id
            AND existing.target_type = 'Task'
            AND existing.target_id = tasks.id
        )
    SQL
  end
end
