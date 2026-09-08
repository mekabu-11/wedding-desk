class CreateSpreadsheetImports < ActiveRecord::Migration[8.1]
  def change
    create_table :spreadsheet_import_batches do |t|
      t.references :wedding, null: false, foreign_key: true
      t.string :digest, null: false
      t.string :mapping_version, null: false
      t.string :state, null: false, default: "pending"
      t.text :source_metadata
      t.text :warnings
      t.integer :row_count, null: false, default: 0
      t.integer :warning_count, null: false, default: 0
      t.integer :imported_count, null: false, default: 0
      t.integer :skipped_count, null: false, default: 0
      t.datetime :committed_at
      t.timestamps
    end
    add_index :spreadsheet_import_batches, [:wedding_id, :digest], unique: true
    add_check_constraint :spreadsheet_import_batches, "state IN ('pending','committed','failed')", name: "spreadsheet_import_batches_valid_state"

    create_table :spreadsheet_import_rows do |t|
      t.references :wedding, null: false, foreign_key: true
      t.references :spreadsheet_import_batch, null: false, foreign_key: true
      t.string :row_kind, null: false
      t.string :sheet_name, null: false
      t.integer :row_number, null: false
      t.string :source_key, null: false
      t.string :state, null: false, default: "pending"
      t.string :target_type
      t.bigint :target_id
      t.text :mapping_label
      t.text :original_data
      t.text :warnings
      t.text :error
      t.timestamps
    end
    add_index :spreadsheet_import_rows, [:spreadsheet_import_batch_id, :source_key], unique: true,
      name: "index_spreadsheet_import_rows_on_batch_and_source_key"
    add_index :spreadsheet_import_rows, [:spreadsheet_import_batch_id, :row_kind, :row_number], unique: true, name: "index_spreadsheet_import_rows_position"
    add_index :spreadsheet_import_rows, [:wedding_id, :state]
    add_check_constraint :spreadsheet_import_rows, "state IN ('pending','ready','skipped','conflict','invalid','imported')", name: "spreadsheet_import_rows_valid_state"
  end
end
