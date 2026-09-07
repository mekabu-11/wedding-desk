class GiftSet < ApplicationRecord
  belongs_to :wedding
  has_many :gift_set_items, dependent: :destroy
  has_many :gift_assignments, dependent: :restrict_with_error

  accepts_nested_attributes_for :gift_set_items, allow_destroy: true, reject_if: :blank_gift_set_item?

  validates :name, presence: true, length: { maximum: 120 }, uniqueness: { scope: :wedding_id }
  encrypts :notes

  def total_price_yen
    gift_set_items.to_a.sum(&:calculated_price_yen)
  end

  def blank_gift_set_item?(attributes)
    attributes["name"].blank?
  end
end
