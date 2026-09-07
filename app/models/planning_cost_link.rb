class PlanningCostLink < ApplicationRecord
  belongs_to :wedding
  belongs_to :planning_item
  belongs_to :budget_item

  validates :planning_item_id, uniqueness: { scope: [:wedding_id, :budget_item_id] }
  validate :references_belong_to_wedding

  private

  def references_belong_to_wedding
    errors.add(:planning_item, "結婚式が一致しません") if planning_item && planning_item.wedding_id != wedding_id
    errors.add(:budget_item, "結婚式が一致しません") if budget_item && budget_item.wedding_id != wedding_id
  end
end
