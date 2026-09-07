class CashGiftRule < ApplicationRecord
  belongs_to :wedding
  has_many :households, dependent: :nullify

  validates :label, presence: true, length: { maximum: 80 }, uniqueness: { scope: :wedding_id }
  validates :default_amount_yen, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  after_update_commit :recalculate_cash_gift_estimates, if: :saved_change_to_default_amount_yen?

  private

  def recalculate_cash_gift_estimates
    BudgetEstimateRecalculator.for_cash_gift_rule_change!(self)
  end
end
