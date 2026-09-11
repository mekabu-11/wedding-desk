class AddFallbackMealsAndSeatingLayout < ActiveRecord::Migration[8.1]
  def change
    add_column :cash_gift_rules, :fallback_attribute, :string
    add_column :cash_gift_rules, :fallback_value, :string
    add_index :cash_gift_rules, [:wedding_id, :fallback_attribute, :fallback_value],
      name: "index_cash_gift_rules_on_fallback_match"

    create_table :meal_sets do |t|
      t.references :wedding, null: false, foreign_key: true
      t.string :name, null: false
      t.string :target_age_group, null: false, default: "adult"
      t.bigint :unit_price_yen, null: false, default: 0
      t.boolean :default_for_target, null: false, default: false
      t.text :notes
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :meal_sets, [:wedding_id, :name], unique: true
    add_index :meal_sets, [:wedding_id, :target_age_group],
      unique: true, where: "default_for_target = TRUE",
      name: "index_meal_sets_on_wedding_and_default_target"
    add_check_constraint :meal_sets, "unit_price_yen >= 0", name: "meal_sets_unit_price_non_negative"
    add_check_constraint :meal_sets, "target_age_group IN ('adult', 'child', 'all')", name: "meal_sets_target_age_group_valid"

    add_reference :guests, :meal_set, foreign_key: true

    add_column :seating_tables, :position_x, :integer
    add_column :seating_tables, :position_y, :integer
    add_check_constraint :seating_tables, "position_x IS NULL OR position_x BETWEEN 0 AND 100",
      name: "seating_tables_position_x_range"
    add_check_constraint :seating_tables, "position_y IS NULL OR position_y BETWEEN 0 AND 100",
      name: "seating_tables_position_y_range"
  end
end
