class BudgetEstimateRecalculator
  class << self
    def for_guest_change!(wedding_id)
      wedding = Wedding.find_by(id: wedding_id)
      return unless wedding

      quantity_estimates(wedding).find_each do |item|
        update_amount!(item, item.calculated_amount)
      end
    end

    def for_cash_gift_rule_change!(rule)
      scope = rule.wedding.budget_items
        .where(certainty: "estimate", source_kind: "cash_gift")
        .where(source_id: rule.wedding.households.where(cash_gift_rule_id: rule.id).select(:id))
      scope.find_each { |item| update_amount!(item, rule.default_amount_yen) }
    end

    def for_gift_set_change!(gift_set_id, wedding_id)
      assignments = GiftAssignment.where(wedding_id: wedding_id, gift_set_id: gift_set_id)
        .includes(gift_set: :gift_set_items)
      assignment_ids = assignments.select(:id)
      budget_items = Wedding.find(wedding_id).budget_items
        .where(certainty: "estimate", source_kind: "gift_assignment", source_id: assignment_ids)
        .index_by(&:source_id)

      assignments.find_each do |assignment|
        item = budget_items[assignment.id]
        update_amount!(item, assignment.total_price_yen) if item
      end
    end

    private

    def quantity_estimates(wedding)
      wedding.budget_items.where(
        certainty: "estimate",
        calculation_mode: "quantity",
        quantity_basis: %w[attending_guests attending_adults attending_children attending_households seating_tables]
      )
    end

    def update_amount!(item, amount)
      return if item.amount_yen == amount

      before = item.amount_yen
      BudgetItem.transaction do
        item.update!(amount_yen: amount)
        ChangeEvent.record!(wedding: item.wedding, target: item, action: "budget_estimate_recalculated",
          before: { amount_yen: before }.to_json, after: { amount_yen: amount }.to_json,
          source: "automatic_recalculation")
      end
    end
  end
end
