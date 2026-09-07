class AddGiftSetItemTaxConstraints < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :gift_set_items,
      "tax_rate IS NULL OR (tax_rate >= 0 AND tax_rate <= 100)",
      name: "gift_set_items_tax_rate_range"
    add_check_constraint :gift_set_items,
      "tax_basis <> 'exclusive' OR tax_rate IS NOT NULL",
      name: "gift_set_items_exclusive_tax_rate_required"
  end
end
