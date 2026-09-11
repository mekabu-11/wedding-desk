class ChangeEvent < ApplicationRecord
  belongs_to :wedding
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :target, polymorphic: true, optional: true

  TARGET_LABELS = {
    "Guest" => ["ゲスト", :name],
    "Task" => ["タスク", :title],
    "BudgetItem" => ["収支項目", :title],
    "Document" => ["資料", :title],
    "PlanningItem" => ["検討項目", :title],
    "PlanningOption" => ["候補", :title],
    "Household" => ["世帯", :name],
    "SeatingTable" => ["卓", :label],
    "GiftSet" => ["引き出物セット", :name]
  }.freeze

  ACTION_LABELS = {
    "guest_attendance_changed" => "出欠を更新",
    "guest_deleted" => "ゲストを削除",
    "document_deleted" => "資料を削除",
    "task_bulk_updated" => "タスクを一括変更",
    "budget_estimate_recalculated" => "収支の見込を更新",
    "planning_option_selected" => "候補を採用",
    "planning_option_rejected" => "候補を見送り",
    "change_set_applied" => "変更を反映"
  }.freeze

  GUEST_CHANGE_LABELS = {
    "attendance" => "出欠",
    "age_group" => "年齢区分",
    "household_id" => "世帯",
    "seating_table_id" => "席次"
  }.freeze

  encrypts :before, :after, :source

  validates :target_type, :action, presence: true, length: { maximum: 80 }
  validates :target_id, numericality: { only_integer: true, greater_than: 0 }

  def self.record!(wedding:, target:, action:, before: nil, after: nil, source: nil, actor: nil)
    create!(wedding: wedding, actor: actor, target_type: target.class.name, target_id: target.id,
      action: action, before: before, after: after, source: source)
  end

  def self.for_target(target)
    where(target_type: target.class.name, target_id: target.id).order(created_at: :desc)
  end

  def subject_label
    label, attribute = TARGET_LABELS.fetch(target_type, ["項目", nil])
    related_target = target if target && (!target.respond_to?(:wedding_id) || target.wedding_id == wedding_id)
    value = related_target.public_send(attribute) if related_target && attribute && related_target.respond_to?(attribute)
    value.present? ? value : "#{label}（削除済み）"
  end

  def action_label
    if action == "guest_attendance_changed"
      changed_fields = GUEST_CHANGE_LABELS.keys & parsed_after.keys
      if changed_fields == ["attendance"] && parsed_after["attendance"].present?
        return "出欠を#{Guest::ATTENDANCES.fetch(parsed_after["attendance"], "更新")}に変更"
      end
      return "#{changed_fields.map { |field| GUEST_CHANGE_LABELS[field] }.join("・")}を変更" if changed_fields.any?
      return "ゲスト情報を変更"
    end

    ACTION_LABELS.fetch(action, "内容を変更")
  end

  private

  def parsed_after
    JSON.parse(after.to_s)
  rescue JSON::ParserError, TypeError
    {}
  end
end
