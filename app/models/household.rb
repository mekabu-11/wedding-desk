class Household < ApplicationRecord
  belongs_to :wedding
  belongs_to :cash_gift_rule, optional: true
  has_many :guests, dependent: :nullify
  has_many :gift_assignments, dependent: :restrict_with_error

  encrypts :name, :notes

  before_validation :assign_code, on: :create
  before_destroy :prevent_destroy_with_cash_gift_budget_item
  validates :code, presence: true, length: { maximum: 50 }, uniqueness: { scope: :wedding_id }
  validates :name, presence: true, length: { maximum: 150 }
  validate :cash_gift_rule_belongs_to_wedding

  scope :active, -> { where(archived: false) }

  def cash_gift_budget_item
    wedding.budget_items.find_by(source_kind: "cash_gift", source_id: id)
  end

  def ensure_cash_gift_budget_item!
    return unless cash_gift_rule

    item = cash_gift_budget_item || wedding.budget_items.build(
      direction: "income", category: "cash_gift", title: "#{name}のご祝儀",
      certainty: "estimate", inclusion: "included", calculation_mode: "manual",
      source_kind: "cash_gift", source_id: id
    )
    item.amount_yen = cash_gift_rule.default_amount_yen if item.new_record? || item.certainty == "estimate"
    item.title = "#{name}のご祝儀"
    item.save!
    item
  end

  private

  def assign_code
    self.code = "household-#{SecureRandom.hex(4)}" if code.blank?
  end

  def prevent_destroy_with_cash_gift_budget_item
    return unless cash_gift_budget_item

    errors.add(:base, "ご祝儀明細がある世帯は削除できません")
    throw(:abort)
  end

  def cash_gift_rule_belongs_to_wedding
    errors.add(:cash_gift_rule, "結婚式が一致しません") if cash_gift_rule && cash_gift_rule.wedding_id != wedding_id
  end
end
