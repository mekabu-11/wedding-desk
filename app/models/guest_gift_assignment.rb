class GuestGiftAssignment < ApplicationRecord
  belongs_to :wedding
  belongs_to :guest
  belongs_to :gift_set
  belongs_to :budget_item, optional: true

  before_destroy :detach_budget_item_source

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :guest_id, uniqueness: { scope: :wedding_id, message: "には既に個人引き出物の割当があります" }
  validate :references_belong_to_wedding

  def total_price_yen
    gift_set.total_price_yen * quantity
  end

  private

  def references_belong_to_wedding
    errors.add(:guest, "結婚式が一致しません") if guest && guest.wedding_id != wedding_id
    errors.add(:gift_set, "結婚式が一致しません") if gift_set && gift_set.wedding_id != wedding_id
    errors.add(:budget_item, "結婚式が一致しません") if budget_item && budget_item.wedding_id != wedding_id
  end

  def detach_budget_item_source
    budget_item&.update!(inclusion: "excluded", source_kind: "manual", source_id: nil)
  end
end
