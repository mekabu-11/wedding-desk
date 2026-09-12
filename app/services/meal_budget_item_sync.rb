class MealBudgetItemSync
  class << self
    def call!(wedding_id)
      wedding = Wedding.find_by(id: wedding_id)
      return unless wedding

      meal_sets = wedding.meal_sets.order(:id).to_a
      return if meal_sets.empty?

      counts = MealSet.attending_guest_counts(wedding, meal_sets)

      meal_sets.each do |meal_set|
        sync_set!(wedding, meal_set, counts[meal_set.id])
      end
    end

    private

    def sync_set!(wedding, meal_set, count)
      item = wedding.budget_items.find_by(source_kind: "meal_set", source_id: meal_set.id)
      if count.positive?
        item ||= wedding.budget_items.build(
          direction: "expense", category: "food", title: "#{meal_set.name}（#{MealSet::TARGET_AGE_GROUPS.fetch(meal_set.target_age_group)}）",
          amount_yen: meal_set.unit_price_yen * count, certainty: "estimate", inclusion: "included",
          calculation_mode: "quantity", quantity_basis: "meal_set", unit_price: meal_set.unit_price_yen,
          tax_basis: "inclusive", source_kind: "meal_set", source_id: meal_set.id
        )
        return item.save! if item.new_record?

        return unless item.certainty == "estimate"
        item.update!(amount_yen: meal_set.unit_price_yen * count, unit_price: meal_set.unit_price_yen,
          title: "#{meal_set.name}（#{MealSet::TARGET_AGE_GROUPS.fetch(meal_set.target_age_group)}）", inclusion: "included")
      elsif item && item.certainty == "estimate" && item.money_movements.empty? && item.inclusion != "excluded"
        before = { inclusion: item.inclusion, amount_yen: item.amount_yen }
        item.update!(inclusion: "excluded")
        ChangeEvent.record!(wedding: wedding, target: item, action: "meal_estimate_excluded",
          before: before.to_json, after: { inclusion: "excluded", amount_yen: item.amount_yen }.to_json,
          source: "automatic_recalculation")
      end
    end
  end
end
