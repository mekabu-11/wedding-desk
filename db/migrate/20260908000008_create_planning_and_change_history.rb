class CreatePlanningAndChangeHistory < ActiveRecord::Migration[8.1]
  def change
    create_table :planning_items do |t|
      t.references :wedding, null: false, foreign_key: true
      t.string :title, null: false
      t.string :category, null: false, default: "other"
      t.text :notes
      t.integer :position, null: false, default: 0
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :planning_items, [:wedding_id, :category, :position, :id]

    create_table :planning_options do |t|
      t.references :wedding, null: false, foreign_key: true
      t.references :planning_item, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.string :status, null: false, default: "draft"
      t.bigint :reference_price_yen
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :planning_options, [:wedding_id, :planning_item_id, :id]
    add_index :planning_options, :planning_item_id, unique: true, where: "status = 'selected'",
      name: "index_planning_options_one_selected_per_item"
    add_check_constraint :planning_options, "status IN ('draft', 'considering', 'selected', 'rejected')",
      name: "planning_options_valid_status"
    add_check_constraint :planning_options, "reference_price_yen IS NULL OR reference_price_yen >= 0",
      name: "planning_options_reference_price_non_negative"

    create_table :music_details do |t|
      t.references :wedding, null: false, foreign_key: true
      t.references :planning_option, null: false, foreign_key: true, index: false
      t.text :wish_track_a
      t.text :wish_track_b
      t.text :selected_track
      t.text :artist
      t.integer :start_offset_seconds
      t.text :original_text
      t.string :scene
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :music_details, :planning_option_id, unique: true
    add_check_constraint :music_details, "start_offset_seconds IS NULL OR start_offset_seconds >= 0",
      name: "music_details_offset_non_negative"

    create_table :planning_cost_links do |t|
      t.references :wedding, null: false, foreign_key: true
      t.references :planning_item, null: false, foreign_key: true
      t.references :budget_item, null: false, foreign_key: true
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :planning_cost_links, [:wedding_id, :planning_item_id, :budget_item_id], unique: true,
      name: "index_planning_cost_links_unique_pair"
    add_index :planning_cost_links, [:wedding_id, :planning_item_id]

    create_table :task_planning_links do |t|
      t.references :wedding, null: false, foreign_key: true
      t.references :task, null: false, foreign_key: true
      t.references :planning_item, null: false, foreign_key: true
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :task_planning_links, [:wedding_id, :task_id, :planning_item_id], unique: true,
      name: "index_task_planning_links_unique_pair"
    add_index :task_planning_links, [:wedding_id, :planning_item_id]

    create_table :change_events do |t|
      t.references :wedding, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :target_type, null: false
      t.bigint :target_id, null: false
      t.string :action, null: false
      t.text :before
      t.text :after
      t.text :source
      t.timestamps
    end
    add_index :change_events, [:wedding_id, :target_type, :target_id, :created_at],
      name: "index_change_events_on_target"
    add_index :change_events, [:wedding_id, :created_at]
  end
end
