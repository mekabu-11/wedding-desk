class CashGiftRule < ApplicationRecord
  FALLBACK_ATTRIBUTES = {
    "none" => "世帯へ手動設定",
    "side" => "新郎側／新婦側",
    "relationship" => "続柄・関係",
    "age_group" => "年齢区分",
    "default" => "その他すべて"
  }.freeze

  belongs_to :wedding
  has_many :households, dependent: :nullify

  validates :label, presence: true, length: { maximum: 80 }, uniqueness: { scope: :wedding_id }
  validates :default_amount_yen, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :fallback_attribute, inclusion: { in: FALLBACK_ATTRIBUTES.keys }, allow_blank: true
  validates :fallback_value, length: { maximum: 150 }
  validate :fallback_value_matches_attribute
  before_validation :normalize_fallback_value
  after_create :recalculate_cash_gift_estimates
  after_update :recalculate_cash_gift_estimates
  after_destroy :recalculate_cash_gift_estimates

  scope :fallback_rules, -> { where.not(fallback_attribute: [nil, "", "none"]) }

  def fallback?
    fallback_attribute.present? && fallback_attribute != "none"
  end

  def matches_guest?(guest)
    return false unless fallback?

    case fallback_attribute
    when "side" then guest.side.to_s == fallback_value.to_s
    when "relationship"
      relationship = guest.relationship.to_s.strip.downcase
      value = fallback_value.to_s.strip.downcase
      value.present? && relationship.include?(value)
    when "age_group" then guest.age_group.to_s == fallback_value.to_s
    when "default" then true
    else false
    end
  end

  def fallback_priority
    { "relationship" => 40, "side" => 30, "age_group" => 20, "default" => 10 }.fetch(fallback_attribute.to_s, 0)
  end

  private

  def recalculate_cash_gift_estimates
    BudgetEstimateRecalculator.for_cash_gift_rule_change!(self)
  end

  def fallback_value_matches_attribute
    return if fallback_attribute.blank? || fallback_attribute.in?(%w[none default])

    errors.add(:fallback_value, "属性を選んだ場合は適用値を入力してください") if fallback_value.blank?
    if fallback_attribute == "side" && fallback_value.present? && !Guest::SIDES.key?(fallback_value)
      errors.add(:fallback_value, "側の値が不正です")
    elsif fallback_attribute == "age_group" && fallback_value.present? && !Guest::AGE_GROUPS.key?(fallback_value)
      errors.add(:fallback_value, "年齢区分の値が不正です")
    end
  end

  def normalize_fallback_value
    self.fallback_value = nil if fallback_attribute.blank? || fallback_attribute.in?(%w[none default])
  end
end
