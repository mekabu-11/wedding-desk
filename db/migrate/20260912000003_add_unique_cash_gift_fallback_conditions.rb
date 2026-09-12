class AddUniqueCashGiftFallbackConditions < ActiveRecord::Migration[8.1]
  def change
    add_index :cash_gift_rules, [:wedding_id, :fallback_attribute, :fallback_value],
      unique: true,
      where: "fallback_attribute IN ('side', 'relationship', 'age_group') AND fallback_value IS NOT NULL",
      name: "index_cash_gift_rules_on_fallback_condition_unique"
    add_index :cash_gift_rules, [:wedding_id, :fallback_attribute],
      unique: true,
      where: "fallback_attribute = 'default'",
      name: "index_cash_gift_rules_on_default_fallback_unique"
  end
end
