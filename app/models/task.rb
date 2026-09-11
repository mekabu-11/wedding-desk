class Task < ApplicationRecord
  ASSIGNEES = { "person_a" => "本人A", "person_b" => "本人B", "both" => "二人", "unknown" => "未設定" }.freeze
  STATUSES = { "todo" => "未着手", "doing" => "進行中", "done" => "完了", "cancelled" => "取り消し" }.freeze
  CATEGORIES = { "venue" => "式場", "guest" => "ゲスト", "food" => "料理", "drink" => "飲み物", "dress" => "ドレス", "tuxedo" => "タキシード", "flower" => "装花", "photo" => "写真", "movie" => "映像", "music" => "音楽", "gift" => "引出物", "invitation" => "招待状", "accommodation" => "宿泊", "insurance" => "保険", "payment" => "支払い", "schedule" => "日程", "other" => "その他" }.freeze
  belongs_to :wedding
  belongs_to :candidate, optional: true
  has_many :task_planning_links, dependent: :destroy
  has_many :planning_items, through: :task_planning_links
  has_many :source_links, as: :target, dependent: :destroy
  encrypts :source_details
  serialize :source_details, coder: JSON
  before_validation :normalize_assignee
  encrypts :title, :description, :original_due_text
  validates :title, presence: true, length: { maximum: 150 }
  validates :description, length: { maximum: 2000 }
  validates :assignee, inclusion: { in: ASSIGNEES.keys }
  validates :status, inclusion: { in: STATUSES.keys }
  validates :category, inclusion: { in: CATEGORIES.keys }
  validate :valid_dates
  validate :same_wedding
  validates :origin, inclusion: { in: %w[ai manual import] }
  validates :source_key, presence: true, if: -> { origin == "import" }
  scope :open_items, -> { where(status: %w[todo doing]) }
  scope :by_deadline, -> { order(Arel.sql("COALESCE(due_at, due_on::timestamp AT TIME ZONE 'Asia/Tokyo') ASC NULLS LAST"), :id) }

  STATUS_SORT_RANK = { "doing" => 0, "todo" => 1, "done" => 2, "cancelled" => 3 }.freeze

  def self.sort_for_gantt(tasks, today: Date.current, now: Time.current)
    tasks.sort_by { |task| gantt_sort_key(task, today: today, now: now) }
  end

  def self.gantt_sort_key(task, today:, now:)
    deadline = task.due_on || task.due_at&.in_time_zone&.to_date
    date_value = deadline || task.starts_on
    due_time = task.due_at&.in_time_zone || date_value&.in_time_zone&.beginning_of_day
    start_date = task.starts_on || date_value
    status_rank = STATUS_SORT_RANK.fetch(task.status, STATUS_SORT_RANK.size)
    far_date = Date.new(9999, 12, 31)
    far_time = Time.zone.local(9999, 12, 31)

    return [4, status_rank, far_time, far_date, task.id] if date_value.nil?

    overdue = deadline.present? && (task.due_at ? task.due_at < now : deadline < today)
    active_today = !overdue && start_date <= today && (deadline.nil? || deadline >= today)
    bucket = if overdue
      0
    elsif active_today
      1
    elsif date_value <= today + 7.days
      2
    else
      3
    end

    # Overdue items are oldest first, active items prioritize progress,
    # and upcoming items are nearest deadline first.
    primary, secondary = if bucket == 1
      [status_rank, due_time || far_time]
    else
      [due_time || far_time, status_rank]
    end
    [bucket, primary, secondary, start_date || far_date, task.id]
  end

  LEGACY_ASSIGNEES = { "self" => "person_a", "partner" => "person_b" }.freeze

  def self.normalize_assignee(value)
    LEGACY_ASSIGNEES.fetch(value.to_s, value.to_s)
  end

  def self.assignee_options(wedding)
    [
      [wedding.self_name.presence || "本人A", "person_a"],
      [wedding.partner_name.presence || "本人B", "person_b"],
      ["二人", "both"],
      ["未設定", "unknown"]
    ]
  end

  def normalize_assignee
    self.assignee = Task.normalize_assignee(assignee)
  end

  def assignee_label
    option = Task.assignee_options(wedding).find { |(_label, value)| value == assignee }
    option&.first || Task::ASSIGNEES[assignee]
  end
  def overdue?
    %w[todo doing].include?(status) && (due_at ? due_at < Time.current : due_on.present? && due_on < Date.current)
  end
  private
  def valid_dates
    [:starts_on, :due_on, :due_at].each do |field|
      errors.add(field, "を正しい形式で入力してください") if public_send("#{field}_before_type_cast").present? && public_send(field).nil?
    end
    raw_datetime = due_at_before_type_cast
    if raw_datetime.is_a?(String) && raw_datetime.present?
      begin
        Date.iso8601(raw_datetime.split("T").first)
      rescue Date::Error
        errors.add(:due_at, "を正しい日付で入力してください")
      end
    end
    errors.add(:base, "期限は日付か日時のどちらかを指定してください") if due_on && due_at
    deadline = due_on || due_at&.in_time_zone&.to_date
    errors.add(:starts_on, "は期限以前の日付にしてください") if starts_on && deadline && starts_on > deadline
  end
  def same_wedding
    errors.add(:candidate, "結婚式が一致しません") if candidate && candidate.document.wedding_id != wedding_id
  end
end
