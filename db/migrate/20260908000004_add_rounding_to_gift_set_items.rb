class AddRoundingToGiftSetItems < ActiveRecord::Migration[8.1]
  def change
    add_column :gift_set_items, :rounding, :string, null: false, default: "floor"
    add_check_constraint :gift_set_items, "rounding IN ('floor', 'round', 'ceil')", name: "gift_set_items_valid_rounding"
  end
end
