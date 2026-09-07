class TaskPlanningLink < ApplicationRecord
  belongs_to :wedding
  belongs_to :task
  belongs_to :planning_item

  validates :task_id, uniqueness: { scope: [:wedding_id, :planning_item_id] }
  validate :references_belong_to_wedding

  private

  def references_belong_to_wedding
    errors.add(:task, "結婚式が一致しません") if task && task.wedding_id != wedding_id
    errors.add(:planning_item, "結婚式が一致しません") if planning_item && planning_item.wedding_id != wedding_id
  end
end
