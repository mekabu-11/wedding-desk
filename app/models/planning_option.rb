class PlanningOption < ApplicationRecord
  STATUSES = { "draft" => "下書き", "considering" => "検討中", "selected" => "採用", "rejected" => "見送り" }.freeze

  belongs_to :wedding
  belongs_to :planning_item
  has_one :music_detail, dependent: :destroy

  encrypts :title, :description

  validates :title, presence: true, length: { maximum: 150 }
  validates :description, length: { maximum: 3000 }
  validates :status, inclusion: { in: STATUSES.keys }
  validates :reference_price_yen, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :same_wedding
  validate :only_one_selected

  STATUSES.each_key { |status| define_method("#{status}?") { self.status == status } }

  private

  def same_wedding
    errors.add(:planning_item, "結婚式が一致しません") if planning_item && planning_item.wedding_id != wedding_id
  end

  def only_one_selected
    return unless status == "selected" && planning_item
    scope = planning_item.planning_options.where(status: "selected").where.not(id: id)
    errors.add(:status, "1項目につき採用は1件までです") if scope.exists?
  end
end
