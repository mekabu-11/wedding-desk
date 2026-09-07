class AdjustBudgetTaxConstraint < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :budget_items, name: "budget_items_exclusive_tax_rate_required"
    add_check_constraint :budget_items,
      "tax_basis <> 'exclusive' OR calculation_mode <> 'quantity' OR tax_rate IS NOT NULL",
      name: "budget_items_exclusive_tax_rate_required"
  end

  def down
    remove_check_constraint :budget_items, name: "budget_items_exclusive_tax_rate_required"
    add_check_constraint :budget_items,
      "tax_basis <> 'exclusive' OR tax_rate IS NOT NULL",
      name: "budget_items_exclusive_tax_rate_required"
  end
end
