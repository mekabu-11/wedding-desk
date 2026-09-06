class Task < ApplicationRecord
  ASSIGNEES = { "self" => "自分", "partner" => "パートナー", "both" => "二人", "unknown" => "未設定" }.freeze
  STATUSES = { "todo" => "未着手", "doing" => "進行中", "done" => "完了", "cancelled" => "取り消し" }.freeze
  CATEGORIES = { "venue" => "式場", "guest" => "ゲスト", "food" => "料理", "drink" => "飲み物", "dress" => "ドレス", "tuxedo" => "タキシード", "flower" => "装花", "photo" => "写真", "movie" => "映像", "music" => "音楽", "gift" => "引出物", "invitation" => "招待状", "accommodation" => "宿泊", "insurance" => "保険", "payment" => "支払い", "schedule" => "日程", "other" => "その他" }.freeze
  belongs_to :wedding
  belongs_to :candidate, optional: true
  encrypts :source_details
  serialize :source_details, coder: JSON
  encrypts :title, :description, :original_due_text
  validates :title, presence: true, length: { maximum: 150 }
  validates :description, length: { maximum: 2000 }
  validates :assignee, inclusion: { in: ASSIGNEES.keys }
  validates :status, inclusion: { in: STATUSES.keys }
  validates :category, inclusion: { in: CATEGORIES.keys }
  validate :valid_dates
  validate :same_wedding
  validates :origin, inclusion: { in: %w[ai manual import] }
  validates :candidate, presence: true, if: -> { origin == "ai" }
  validates :source_key, presence: true, if: -> { origin == "import" }
  scope :open_items, -> { where(status: %w[todo doing]) }
  scope :by_deadline, -> { order(Arel.sql("COALESCE(due_at, due_on::timestamp AT TIME ZONE 'Asia/Tokyo') ASC NULLS LAST"), :id) }
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
