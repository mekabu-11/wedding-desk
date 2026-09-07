class PlanningItem < ApplicationRecord
  CATEGORIES = {
    "production" => "演出", "music" => "BGM", "dress" => "衣装", "beauty" => "美容",
    "flower" => "装花", "food" => "料理", "photo" => "写真", "movie" => "映像",
    "paper" => "ペーパー", "gift" => "ギフト", "other" => "その他"
  }.freeze

  belongs_to :wedding
  has_many :planning_options, dependent: :destroy
  has_many :planning_cost_links, dependent: :destroy
  has_many :budget_items, through: :planning_cost_links
  has_many :task_planning_links, dependent: :destroy
  has_many :tasks, through: :task_planning_links

  encrypts :title, :notes

  validates :title, presence: true, length: { maximum: 150 }
  validates :category, inclusion: { in: CATEGORIES.keys }
  validates :notes, length: { maximum: 3000 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
