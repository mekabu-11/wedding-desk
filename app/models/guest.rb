class Guest < ApplicationRecord
  SIDES = { "bride" => "新婦側", "groom" => "新郎側", "unknown" => "未設定" }.freeze
  AGE_GROUPS = { "adult" => "大人", "child" => "子ども" }.freeze
  ATTENDANCES = { "attending" => "出席", "declined" => "欠席", "pending" => "保留", "unanswered" => "未回答" }.freeze
  GENDERS = { "female" => "女性", "male" => "男性", "other" => "その他", "unknown" => "未設定" }.freeze
  INVITATION_STATUSES = { "planned" => "招待予定", "invited" => "招待済み", "unknown" => "未設定" }.freeze
  ROLES = { "reception" => "受付", "speech" => "スピーチ", "toast" => "乾杯", "performance" => "余興", "escort" => "中座エスコート", "other" => "その他" }.freeze

  belongs_to :wedding
  belongs_to :household, optional: true
  belongs_to :seating_table, optional: true

  encrypts :name, :relationship, :roles, :allergies, :notes
  serialize :roles, coder: JSON
  before_validation :inherit_wedding, on: :create
  before_validation :normalize_roles
  after_commit :recalculate_budget_estimates_after_change

  validates :name, presence: true, length: { maximum: 150 }
  validates :side, inclusion: { in: SIDES.keys }
  validates :age_group, inclusion: { in: AGE_GROUPS.keys }
  validates :attendance, inclusion: { in: ATTENDANCES.keys }
  validates :gender, inclusion: { in: GENDERS.keys }, allow_blank: true
  validates :invitation_status, inclusion: { in: INVITATION_STATUSES.keys }, allow_blank: true
  validate :roles_are_known
  validate :related_records_belong_to_wedding

  scope :ordered, -> { order(:id) }
  scope :attending, -> { where(attendance: "attending") }

  private

  def inherit_wedding
    self.wedding ||= household&.wedding || seating_table&.wedding
  end

  def normalize_roles
    self.roles = Array(roles).reject(&:blank?)
  end

  def roles_are_known
    Array(roles).each do |role|
      errors.add(:roles, "に未対応の役割があります") unless ROLES.key?(role)
    end
  end

  def related_records_belong_to_wedding
    errors.add(:household, "結婚式が一致しません") if household && household.wedding_id != wedding_id
    errors.add(:seating_table, "結婚式が一致しません") if seating_table && seating_table.wedding_id != wedding_id
  end

  def recalculate_budget_estimates_after_change
    return unless destroyed? || previous_changes.key?("id") ||
      (previous_changes.keys & %w[attendance age_group household_id seating_table_id]).any?

    BudgetEstimateRecalculator.for_guest_change!(wedding_id)
  end
end
