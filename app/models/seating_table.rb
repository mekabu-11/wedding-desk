class SeatingTable < ApplicationRecord
  belongs_to :wedding
  has_many :guests, dependent: :nullify

  validates :label, presence: true, length: { maximum: 80 }, uniqueness: { scope: :wedding_id }
  validates :capacity, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
end
