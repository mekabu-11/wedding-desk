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
    "seating_table_id" => "卓",
    "gender" => "性別",
    "invitation_status" => "招待状",
    "roles" => "役割"
  }.freeze

  FIELD_LABELS = {
    "title" => "タイトル",
    "description" => "説明",
    "status" => "状態",
    "assignee" => "担当",
    "category" => "カテゴリ",
    "amount_yen" => "金額",
    "certainty" => "確度",
    "inclusion" => "集計",
    "direction" => "区分",
    "source_kind" => "情報元",
    "cost_mode" => "費用処理",
    "selected_option_id" => "採用候補"
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

  def detail_label
    changes = parsed_changes.filter_map do |field, values|
      next if values[:before] == values[:after]

      "#{field_label(field)}：#{display_value(field, values[:before])} → #{display_value(field, values[:after])}"
    end
    return if changes.empty?

    shown = changes.first(3)
    remaining = changes.size - shown.size
    remaining.positive? ? "#{shown.join(' / ')} / ほか#{remaining}項目" : shown.join(" / ")
  end

  private

  def parsed_changes
    before_values = parsed_json(before)
    after_values = parsed_json(after)
    (before_values.keys | after_values.keys).index_with do |field|
      { before: before_values[field], after: after_values[field] }
    end
  end

  def parsed_json(value)
    JSON.parse(value.to_s)
  rescue JSON::ParserError, TypeError
    {}
  end

  def field_label(field)
    FIELD_LABELS[field] || GUEST_CHANGE_LABELS[field] || field.to_s.humanize
  end

  def display_value(field, value)
    return "未設定" if value.blank?

    case target_type
    when "Guest"
      return guest_value_label(field, value)
    when "Task"
      return Task::STATUSES.fetch(value, value) if field == "status"
      return Task::CATEGORIES.fetch(value, value) if field == "category"
      return Task.assignee_options(wedding).to_h.invert[value] || Task::ASSIGNEES.fetch(value, value) if field == "assignee"
    when "BudgetItem"
      return BudgetItem::DIRECTIONS.fetch(value, value) if field == "direction"
      return BudgetItem::CERTAINTIES.fetch(value, value) if field == "certainty"
      return BudgetItem::INCLUSIONS.fetch(value, value) if field == "inclusion"
      return BudgetItem::SOURCE_KINDS.fetch(value, value) if field == "source_kind"
      return "#{ActiveSupport::NumberHelper.number_to_delimited(value.to_i)}円" if field == "amount_yen"
    when "PlanningOption"
      return PlanningOption::STATUSES.fetch(value, value) if field == "status"
      return PlanningOption.find_by(wedding_id: wedding_id, id: value)&.title || "候補 ##{value}" if field == "selected_option_id"
    end

    return "#{ActiveSupport::NumberHelper.number_to_delimited(value.to_i)}円" if field == "amount_yen"
    value.is_a?(Array) ? value.join("、") : value.to_s.truncate(80)
  end

  def guest_value_label(field, value)
    case field
    when "attendance" then Guest::ATTENDANCES.fetch(value, value)
    when "age_group" then Guest::AGE_GROUPS.fetch(value, value)
    when "gender" then Guest::GENDERS.fetch(value, value)
    when "invitation_status" then Guest::INVITATION_STATUSES.fetch(value, value)
    when "household_id"
      wedding.households.find_by(id: value)&.name || "世帯 ##{value}"
    when "seating_table_id"
      wedding.seating_tables.find_by(id: value)&.label || "卓 ##{value}"
    else
      value.is_a?(Array) ? value.join("、") : value.to_s.truncate(80)
    end
  end

  def parsed_after
    parsed_json(after)
  end
end
