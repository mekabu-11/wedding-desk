class MoneyMovement < ApplicationRecord
  KINDS = { "payment" => "支払い", "receipt" => "受取", "refund" => "返金", "return" => "返戻" }.freeze

  belongs_to :wedding
  belongs_to :budget_item

  encrypts :note

  validates :occurred_on, presence: true
  validates :kind, inclusion: { in: KINDS.keys }
  validates :amount_yen, numericality: { only_integer: true, greater_than: 0 }
  validates :idempotency_key, length: { maximum: 120 }, uniqueness: { scope: :wedding_id }, allow_nil: true
  validate :budget_item_belongs_to_wedding
  validate :kind_matches_direction
  validate :refund_or_return_does_not_exceed_history

  private

  def budget_item_belongs_to_wedding
    errors.add(:budget_item, "結婚式が一致しません") if budget_item && budget_item.wedding_id != wedding_id
  end

  def kind_matches_direction
    return unless budget_item
    allowed = budget_item.direction == "expense" ? %w[payment refund] : %w[receipt return]
    errors.add(:kind, "収支の種類が一致しません") unless allowed.include?(kind)
  end

  def refund_or_return_does_not_exceed_history
    return unless %w[refund return].include?(kind) && budget_item
    prior_kind = kind == "refund" ? "payment" : "receipt"
    prior_total = budget_item.money_movements.where(kind: prior_kind).where.not(id: id).sum(:amount_yen)
    used_total = budget_item.money_movements.where(kind: kind).where.not(id: id).sum(:amount_yen)
    errors.add(:amount_yen, "過去の#{KINDS[kind]}を超えています") if amount_yen.to_i + used_total > prior_total
  end
end
