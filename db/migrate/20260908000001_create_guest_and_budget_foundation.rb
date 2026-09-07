class CreateGuestAndBudgetFoundation < ActiveRecord::Migration[8.1]
  def change
    create_table :seating_tables do |t|
      t.references :wedding, null: false, foreign_key: true
      t.string :label, null: false
      t.integer :capacity
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :seating_tables, [:wedding_id, :label], unique: true

    create_table :cash_gift_rules do |t|
      t.references :wedding, null: false, foreign_key: true
      t.string :label, null: false
      t.bigint :default_amount_yen, null: false
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :cash_gift_rules, [:wedding_id, :label], unique: true
    add_check_constraint :cash_gift_rules, "default_amount_yen >= 0", name: "cash_gift_rules_amount_non_negative"

    create_table :households do |t|
      t.references :wedding, null: false, foreign_key: true
      t.string :code, null: false
      t.text :name, null: false
      t.references :cash_gift_rule, foreign_key: true
      t.text :notes
      t.boolean :archived, null: false, default: false
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :households, [:wedding_id, :code], unique: true

    create_table :guests do |t|
      t.references :wedding, null: false, foreign_key: true
      t.references :household, foreign_key: true
      t.references :seating_table, foreign_key: true
      t.text :name, null: false
      t.string :side, null: false, default: "unknown"
      t.text :relationship
      t.string :gender
      t.string :age_group, null: false, default: "adult"
      t.string :attendance, null: false, default: "unanswered"
      t.string :invitation_status
      t.text :roles
      t.text :allergies
      t.text :notes
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :guests, [:wedding_id, :household_id]
    add_index :guests, [:wedding_id, :attendance]

    create_table :budget_items do |t|
      t.references :wedding, null: false, foreign_key: true
      t.string :direction, null: false
      t.string :category, null: false, default: "other"
      t.text :title, null: false
      t.bigint :amount_yen
      t.string :certainty, null: false, default: "estimate"
      t.string :inclusion, null: false, default: "included"
      t.string :calculation_mode, null: false, default: "manual"
      t.string :quantity_basis
      t.bigint :unit_price
      t.integer :manual_quantity
      t.string :tax_basis, null: false, default: "unknown"
      t.decimal :tax_rate, precision: 5, scale: 2
      t.string :rounding, null: false, default: "floor"
      t.string :source_kind, null: false, default: "manual"
      t.bigint :source_id
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :budget_items, [:wedding_id, :direction, :inclusion]
    add_index :budget_items, [:wedding_id, :source_kind, :source_id], unique: true,
      where: "source_kind <> 'manual' AND source_id IS NOT NULL",
      name: "index_budget_items_on_wedding_and_source"
    add_check_constraint :budget_items, "amount_yen IS NULL OR amount_yen >= 0", name: "budget_items_amount_non_negative"
    add_check_constraint :budget_items, "source_kind = 'manual' OR source_id IS NOT NULL", name: "budget_items_source_required"

    create_table :money_movements do |t|
      t.references :wedding, null: false, foreign_key: true
      t.references :budget_item, null: false, foreign_key: true
      t.date :occurred_on, null: false
      t.string :kind, null: false
      t.bigint :amount_yen, null: false
      t.text :note
      t.string :idempotency_key
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :money_movements, [:wedding_id, :budget_item_id, :occurred_on]
    add_index :money_movements, [:wedding_id, :idempotency_key], unique: true, where: "idempotency_key IS NOT NULL"
    add_check_constraint :money_movements, "amount_yen > 0", name: "money_movements_amount_positive"

    create_table :gift_sets do |t|
      t.references :wedding, null: false, foreign_key: true
      t.string :name, null: false
      t.text :notes
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :gift_sets, [:wedding_id, :name], unique: true

    create_table :gift_set_items do |t|
      t.references :gift_set, null: false, foreign_key: true
      t.string :kind, null: false, default: "other"
      t.string :name, null: false
      t.bigint :unit_price_yen, null: false, default: 0
      t.string :tax_basis, null: false, default: "unknown"
      t.decimal :tax_rate, precision: 5, scale: 2
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    create_table :gift_assignments do |t|
      t.references :wedding, null: false, foreign_key: true
      t.references :household, null: false, foreign_key: true
      t.references :gift_set, null: false, foreign_key: true
      t.references :budget_item, foreign_key: true, index: false
      t.integer :quantity, null: false, default: 1
      t.boolean :included, null: false, default: true
      t.text :notes
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :gift_assignments, [:wedding_id, :household_id], unique: true
    add_index :gift_assignments, :budget_item_id, unique: true, where: "budget_item_id IS NOT NULL"
    add_check_constraint :gift_assignments, "quantity > 0", name: "gift_assignments_quantity_positive"
  end
end
