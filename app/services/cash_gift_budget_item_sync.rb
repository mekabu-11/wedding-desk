class CashGiftBudgetItemSync
  class << self
    def for_guest_change!(guest)
      wedding = Wedding.find_by(id: guest.wedding_id)
      return unless wedding

      item = wedding.budget_items.find_by(source_kind: "cash_gift_guest", source_id: guest.id)
      rule = fallback_rule_for(wedding, guest)
      if guest.persisted? && guest.household_id.blank? && guest.attendance == "attending" && rule
        ensure_item!(wedding, guest, rule, item)
      else
        exclude_item!(item) if item
      end
    end

    def for_rule_change!(rule)
      rule.wedding.guests.where(household_id: nil).find_each { |guest| for_guest_change!(guest) }
    end

    private

    def fallback_rule_for(wedding, guest)
      wedding.cash_gift_rules.fallback_rules
        .select { |rule| rule.matches_guest?(guest) }
        .sort_by { |rule| [-rule.fallback_priority, rule.id] }
        .first
    end

    def ensure_item!(wedding, guest, rule, item)
      item ||= wedding.budget_items.build(
        direction: "income", category: "cash_gift", title: "#{guest.name}のご祝儀",
        amount_yen: rule.default_amount_yen, certainty: "estimate", inclusion: "included",
        calculation_mode: "manual", source_kind: "cash_gift_guest", source_id: guest.id
      )
      if item.new_record?
        item.save!
        ChangeEvent.record!(wedding: wedding, target: item, action: "cash_gift_fallback_applied",
          after: { amount_yen: item.amount_yen, inclusion: item.inclusion, rule_id: rule.id }.to_json,
          source: "automatic_recalculation")
        return item
      end

      return unless item.certainty == "estimate"

      before = { amount_yen: item.amount_yen, inclusion: item.inclusion }
      item.assign_attributes(amount_yen: rule.default_amount_yen, title: "#{guest.name}のご祝儀", inclusion: "included")
      return if item.changes.empty?

      item.save!
      ChangeEvent.record!(wedding: wedding, target: item, action: "cash_gift_fallback_applied",
        before: before.to_json, after: { amount_yen: item.amount_yen, inclusion: item.inclusion, rule_id: rule.id }.to_json,
        source: "automatic_recalculation")
    end

    def exclude_item!(item)
      return unless item.persisted? && item.certainty == "estimate" && item.money_movements.empty?
      return if item.inclusion == "excluded"

      before = { inclusion: item.inclusion }
      item.update!(inclusion: "excluded")
      ChangeEvent.record!(wedding: item.wedding, target: item, action: "cash_gift_fallback_excluded",
        before: before.to_json, after: { inclusion: "excluded" }.to_json, source: "automatic_recalculation")
    end
  end
end
