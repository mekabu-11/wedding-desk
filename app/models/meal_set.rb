class MealSet < ApplicationRecord
  TARGET_AGE_GROUPS = { "adult" => "大人", "child" => "子ども", "all" => "全員" }.freeze

  belongs_to :wedding
  has_many :guests, dependent: :nullify

  encrypts :notes

  validates :name, presence: true, length: { maximum: 120 }, uniqueness: { scope: :wedding_id }
  validates :target_age_group, inclusion: { in: TARGET_AGE_GROUPS.keys }
  validates :unit_price_yen, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :only_one_default_for_target

  after_create :sync_budget_items
  after_update :sync_budget_items
  before_destroy :detach_budget_items
  after_destroy :sync_budget_items

  scope :ordered, -> { order(:target_age_group, :id) }

  def self.default_for(wedding, age_group)
    specific = wedding.meal_sets.find_by(target_age_group: age_group, default_for_target: true)
    specific || wedding.meal_sets.find_by(target_age_group: "all", default_for_target: true)
  end

  def attending_guest_count
    wedding.guests.attending.includes(:meal_set).count { |guest| guest.effective_meal_set == self }
  end

  private

  def only_one_default_for_target
    return unless default_for_target? && wedding

    duplicate = wedding.meal_sets.where(target_age_group: target_age_group, default_for_target: true).where.not(id: id).exists?
    errors.add(:default_for_target, "同じ対象の標準セットは1つだけ設定できます") if duplicate
  end

  def sync_budget_items
    MealBudgetItemSync.call!(wedding_id)
  end

  def detach_budget_items
    wedding.budget_items.where(source_kind: "meal_set", source_id: id).find_each do |item|
      before = { source_kind: item.source_kind, source_id: item.source_id, inclusion: item.inclusion, amount_yen: item.amount_yen }
      if item.certainty == "estimate" && item.money_movements.empty?
        item.update!(inclusion: "excluded", source_kind: "manual", source_id: nil)
        action = "meal_estimate_excluded"
      else
        item.update!(source_kind: "manual", source_id: nil)
        action = "meal_source_detached"
      end
      ChangeEvent.record!(wedding: wedding, target: item, action: action,
        before: before.to_json, after: { source_kind: item.source_kind, source_id: item.source_id, inclusion: item.inclusion, amount_yen: item.amount_yen }.to_json,
        source: "meal_set_deleted")
    end
  end
end
