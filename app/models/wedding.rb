class Wedding < ApplicationRecord
  has_many :memberships, dependent: :destroy, inverse_of: :wedding
  has_many :users, through: :memberships
  has_many :documents, dependent: :destroy
  has_many :tasks, dependent: :destroy
  has_many :task_imports, dependent: :destroy
  has_many :seating_tables, dependent: :destroy
  has_many :cash_gift_rules, dependent: :destroy
  has_many :households, dependent: :destroy
  has_many :guests, dependent: :destroy
  has_many :budget_items, dependent: :destroy
  has_many :money_movements, dependent: :destroy
  has_many :gift_sets, dependent: :destroy
  has_many :gift_assignments, dependent: :destroy
  has_many :planning_items, dependent: :destroy
  has_many :planning_options, dependent: :destroy
  has_many :music_details, dependent: :destroy
  has_many :planning_cost_links, dependent: :destroy
  has_many :task_planning_links, dependent: :destroy
  has_many :change_events, dependent: :destroy
  has_many :source_links, dependent: :destroy
  has_many :change_sets, dependent: :destroy
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
