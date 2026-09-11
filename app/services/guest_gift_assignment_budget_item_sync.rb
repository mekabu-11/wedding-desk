class GuestGiftAssignmentBudgetItemSync
  def self.call!(assignment)
    new(assignment).call!
  end

  def initialize(assignment)
    @assignment = assignment
    @wedding = assignment.wedding
  end

  def call!
    item = @assignment.budget_item || @wedding.budget_items.build(
      direction: "expense", category: "gift", certainty: "estimate",
      inclusion: @assignment.included? ? "included" : "excluded",
      calculation_mode: "manual", tax_basis: "unknown", rounding: "floor",
      source_kind: "guest_gift_assignment", source_id: @assignment.id
    )
    item.amount_yen = @assignment.total_price_yen if item.new_record? || item.certainty == "estimate"
    item.title = "#{@assignment.guest.name}の引き出物"
    item.inclusion = @assignment.included? ? "included" : "excluded"
    item.source_kind = "guest_gift_assignment"
    item.source_id = @assignment.id
    item.save!
    @assignment.update!(budget_item: item) unless @assignment.budget_item_id == item.id
    item
  end
end
