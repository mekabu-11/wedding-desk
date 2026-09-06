class Wedding < ApplicationRecord
  belongs_to :user
  has_many :documents, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_many :task_imports, dependent: :destroy
  validate :valid_wedding_date
  def valid_wedding_date
    if wedding_date_before_type_cast.present? && wedding_date.nil?
      errors.add(:wedding_date, "を正しい日付で入力してください")
    end
  end
  validates :name, presence: true, length: { maximum: 100 }
  validates :venue_name, :self_name, :partner_name, length: { maximum: 150 }
  validates :budget_yen, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 10**12 }, allow_nil: true
end
