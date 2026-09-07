class GiftSetItem < ApplicationRecord
  KINDS = { "gift" => "引出物", "sweet" => "引菓子", "celebration" => "縁起物", "other" => "その他" }.freeze
  TAX_BASES = BudgetItem::TAX_BASES
  ROUNDINGS = { "floor" => "切捨て", "round" => "四捨五入", "ceil" => "切上げ" }.freeze

  belongs_to :gift_set
  encrypts :name
  validates :kind, inclusion: { in: KINDS.keys }
  validates :name, presence: true, length: { maximum: 120 }
  validates :unit_price_yen, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :tax_basis, inclusion: { in: TAX_BASES.keys }
  validates :tax_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :rounding, inclusion: { in: ROUNDINGS.keys }
  validate :exclusive_tax_rate_required
  after_commit :recalculate_gift_estimates

  def calculated_price_yen
    return unit_price_yen.to_i unless tax_basis == "exclusive" && tax_rate.present?

    taxable = BigDecimal(unit_price_yen.to_i.to_s) * (BigDecimal("1") + BigDecimal(tax_rate.to_s) / 100)
    case rounding
    when "ceil" then taxable.ceil
    when "round" then taxable.round(0, BigDecimal::ROUND_HALF_UP).to_i
    else taxable.floor
    end
  end

  private

  def exclusive_tax_rate_required
    errors.add(:tax_rate, "税抜の場合は税率を入力してください") if tax_basis == "exclusive" && tax_rate.blank?
  end

  def recalculate_gift_estimates
    return unless destroyed? || previous_changes.key?("id") ||
      (previous_changes.keys & %w[unit_price_yen tax_basis tax_rate rounding]).any?

    BudgetEstimateRecalculator.for_gift_set_change!(gift_set_id, gift_set.wedding_id)
  end
end
