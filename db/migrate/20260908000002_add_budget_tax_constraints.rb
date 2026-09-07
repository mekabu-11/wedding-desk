class AddBudgetTaxConstraints < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :budget_items,
      "tax_rate IS NULL OR (tax_rate >= 0 AND tax_rate <= 100)",
      name: "budget_items_tax_rate_range"
    add_check_constraint :budget_items,
      "tax_basis <> 'exclusive' OR calculation_mode <> 'quantity' OR tax_rate IS NOT NULL",
      name: "budget_items_exclusive_tax_rate_required"
  end
end
