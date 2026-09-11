class CreateGuestGiftAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :guest_gift_assignments do |t|
      t.references :wedding, null: false, foreign_key: true
      t.references :guest, null: false, foreign_key: true
      t.references :gift_set, null: false, foreign_key: true
      t.references :budget_item, foreign_key: true, index: false
      t.integer :quantity, null: false, default: 1
      t.boolean :included, null: false, default: true
      t.text :notes
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :guest_gift_assignments, [:wedding_id, :guest_id], unique: true
    add_index :guest_gift_assignments, :budget_item_id, unique: true, where: "budget_item_id IS NOT NULL"
    add_check_constraint :guest_gift_assignments, "quantity > 0", name: "guest_gift_assignments_quantity_positive"
  end
end
