class BudgetItem < ApplicationRecord
  DIRECTIONS = { "income" => "収入", "expense" => "支出" }.freeze
  CERTAINTIES = { "estimate" => "概算", "confirmed" => "確定" }.freeze
  INCLUSIONS = { "included" => "集計する", "excluded" => "除外" }.freeze
  CALCULATION_MODES = { "manual" => "金額を直接入力", "quantity" => "単価×数量" }.freeze
  QUANTITY_BASES = {
    "manual" => "手動数量", "attending_guests" => "出席ゲスト", "attending_adults" => "出席大人",
    "attending_children" => "出席子ども", "attending_households" => "出席世帯", "seating_tables" => "使用テーブル"
  }.freeze
  TAX_BASES = { "inclusive" => "税込", "exclusive" => "税抜", "unknown" => "不明" }.freeze
  CATEGORY_LABELS = {
    "venue" => "会場", "food" => "料理", "drink" => "飲み物", "gift" => "引き出物", "cash_gift" => "ご祝儀",
    "travel" => "お車代", "production" => "演出", "music" => "音楽", "dress" => "衣装", "photo" => "写真",
    "movie" => "映像", "invitation" => "招待状", "accommodation" => "宿泊", "other" => "その他"
  }.freeze
  SOURCE_KINDS = { "manual" => "手動", "planning_option" => "検討候補", "cash_gift" => "ご祝儀", "travel_guest" => "個人のお車代", "travel_household" => "世帯のお車代", "gift_assignment" => "引き出物割当", "guest_gift_assignment" => "個人引き出物割当" }.freeze
  PAYMENT_STATUS_FILTERS = {
    "unsettled" => "未処理",
    "partial" => "一部処理",
    "completed" => "完了",
    "unknown" => "金額未確認",
    "overpaid" => "要確認"
  }.freeze

  belongs_to :wedding
  has_many :money_movements, dependent: :restrict_with_error
  has_one :gift_assignment, dependent: :nullify
  has_one :guest_gift_assignment, dependent: :nullify
  has_many :planning_cost_links, dependent: :destroy
  has_many :planning_items, through: :planning_cost_links

  encrypts :title

  validates :direction, inclusion: { in: DIRECTIONS.keys }
  validates :category, presence: true, length: { maximum: 80 }
  validates :title, presence: true, length: { maximum: 150 }
  validates :certainty, inclusion: { in: CERTAINTIES.keys }
  validates :inclusion, inclusion: { in: INCLUSIONS.keys }
  validates :calculation_mode, inclusion: { in: CALCULATION_MODES.keys }
  validates :quantity_basis, inclusion: { in: QUANTITY_BASES.keys }, allow_nil: true
  validates :amount_yen, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :unit_price, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :manual_quantity, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :tax_basis, inclusion: { in: TAX_BASES.keys }
  validates :rounding, inclusion: { in: %w[floor round ceil] }
  validates :tax_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :source_kind, inclusion: { in: SOURCE_KINDS.keys }
  validate :amount_rules
  validate :source_belongs_to_wedding
  before_validation :derive_quantity_amount

  scope :included, -> { where(inclusion: "included") }
  scope :expenses, -> { where(direction: "expense") }
  scope :income, -> { where(direction: "income") }

  def calculated_amount
    return amount_yen if calculation_mode == "manual" || unit_price.nil? || effective_quantity.nil?
    base = unit_price * effective_quantity
    return base unless tax_basis == "exclusive" && tax_rate.present?

    taxable = BigDecimal(base.to_s) * (BigDecimal("1") + BigDecimal(tax_rate.to_s) / 100)
    case rounding
    when "ceil" then taxable.ceil
    when "round" then taxable.round(0, BigDecimal::ROUND_HALF_UP).to_i
    else taxable.floor
    end
  end

  def effective_quantity
    return manual_quantity if quantity_basis.blank? || quantity_basis == "manual"
    case quantity_basis
    when "attending_guests" then wedding.guests.attending.count
    when "attending_adults" then wedding.guests.attending.where(age_group: "adult").count
    when "attending_children" then wedding.guests.attending.where(age_group: "child").count
    when "attending_households" then wedding.guests.attending.where.not(household_id: nil).distinct.count(:household_id)
    when "seating_tables" then wedding.seating_tables.joins(:guests).merge(Guest.attending).distinct.count
    end
  end

  def net_movement_amount
    money_movements.sum do |movement|
      %w[refund return].include?(movement.kind) ? -movement.amount_yen : movement.amount_yen
    end
  end

  def remaining_amount
    return nil if amount_yen.nil?
    amount_yen - net_movement_amount
  end

  def payment_status
    case payment_status_key
    when "unknown" then "金額未確認"
    when "not_required" then direction == "income" ? "受取不要" : "支払い不要"
    when "unsettled" then direction == "income" ? "未受取" : "未払い"
    when "partial" then direction == "income" ? "一部受取" : "一部"
    when "completed" then direction == "income" ? "受取完了" : "完了"
    when "overpaid" then "超過・要確認"
    else "要確認"
    end
  end

  def payment_status_key
    return "unknown" if amount_yen.nil?
    return "not_required" if amount_yen.zero? && money_movements.empty?
    net = net_movement_amount
    return "unsettled" if net.zero?
    return "partial" if net < amount_yen
    return "completed" if net == amount_yen
    "overpaid"
  end

  private

  def amount_rules
    if certainty == "confirmed" && amount_yen.nil?
      errors.add(:amount_yen, "確定の場合は金額を入力してください")
    end
    if calculation_mode == "quantity"
      errors.add(:unit_price, "単価を入力してください") if unit_price.nil?
      errors.add(:quantity_basis, "数量基準を入力してください") if quantity_basis.blank?
      errors.add(:manual_quantity, "手動数量を入力してください") if quantity_basis == "manual" && manual_quantity.blank?
    end
    errors.add(:tax_rate, "税抜の単価計算には税率を入力してください") if calculation_mode == "quantity" && tax_basis == "exclusive" && tax_rate.nil?
  end

  def derive_quantity_amount
    self.amount_yen = calculated_amount if calculation_mode == "quantity" && certainty == "estimate" && unit_price.present? && effective_quantity.present?
  end

  def source_belongs_to_wedding
    return if source_kind == "manual" && source_id.blank?
    errors.add(:source_id, "元データを指定してください") if source_id.blank?
    return if source_id.blank?

    record = case source_kind
    when "planning_option" then PlanningOption.find_by(id: source_id)
    when "cash_gift", "travel_household" then Household.find_by(id: source_id)
    when "travel_guest" then Guest.find_by(id: source_id)
    when "gift_assignment" then GiftAssignment.find_by(id: source_id)
    when "guest_gift_assignment" then GuestGiftAssignment.find_by(id: source_id)
    end
    errors.add(:source_id, "結婚式が一致しません") if record.nil? || record.wedding_id != wedding_id
  end
end
