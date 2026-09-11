class ChangeEvent < ApplicationRecord
  belongs_to :wedding
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :target, polymorphic: true, optional: true

  TARGET_LABELS = {
    "Guest" => ["ゲスト", :name],
    "Task" => ["タスク", :title],
    "BudgetItem" => ["収支項目", :title],
    "MoneyMovement" => ["入出金履歴", nil],
    "Document" => ["資料", :title],
    "PlanningItem" => ["検討項目", :title],
    "PlanningOption" => ["候補", :title],
    "Household" => ["世帯", :name],
    "SeatingTable" => ["卓", :label],
    "CashGiftRule" => ["ご祝儀区分", :label],
    "GiftSet" => ["引き出物セット", :name],
    "GiftAssignment" => ["引き出物割当", nil],
    "GuestGiftAssignment" => ["個人引き出物割当", nil],
    "MusicDetail" => ["BGM情報", nil]
  }.freeze

  ACTION_LABELS = {
    "guest_attendance_changed" => "出欠を更新",
    "guest_deleted" => "ゲストを削除",
    "task_created" => "タスクを追加",
    "task_updated" => "タスクを更新",
    "document_deleted" => "資料を削除",
    "document_created" => "資料を追加",
    "task_bulk_updated" => "タスクを一括変更",
    "budget_item_created" => "収支項目を追加",
    "budget_item_updated" => "収支項目を更新",
    "budget_item_deleted" => "収支項目を削除",
    "money_movement_created" => "入出金履歴を追加",
    "money_movement_updated" => "入出金履歴を更新",
    "money_movement_deleted" => "入出金履歴を削除",
    "budget_estimate_recalculated" => "収支の見込を更新",
    "household_created" => "世帯を追加",
    "household_updated" => "世帯を更新",
    "household_deleted" => "世帯を削除",
    "seating_table_created" => "卓を追加",
    "seating_table_updated" => "卓を更新",
    "seating_table_deleted" => "卓を削除",
    "cash_gift_rule_created" => "ご祝儀区分を追加",
    "cash_gift_rule_updated" => "ご祝儀区分を更新",
    "cash_gift_rule_deleted" => "ご祝儀区分を削除",
    "gift_set_created" => "引き出物セットを追加",
    "gift_set_updated" => "引き出物セットを更新",
    "gift_set_deleted" => "引き出物セットを削除",
    "gift_assignment_created" => "引き出物を割当",
    "gift_assignment_updated" => "引き出物割当を更新",
    "gift_assignment_deleted" => "引き出物割当を解除",
    "guest_gift_assignment_created" => "個人引き出物を割当",
    "guest_gift_assignment_updated" => "個人引き出物割当を更新",
    "guest_gift_assignment_deleted" => "個人引き出物割当を解除",
    "planning_item_created" => "検討項目を追加",
    "planning_item_updated" => "検討項目を更新",
    "planning_item_deleted" => "検討項目を削除",
    "planning_option_created" => "候補を追加",
    "planning_option_updated" => "候補を更新",
    "planning_option_deleted" => "候補を削除",
    "planning_option_selected" => "候補を採用",
    "planning_option_cost_changed" => "候補に伴う費用を更新",
    "planning_option_cost_excluded" => "旧候補の概算費用を除外",
    "planning_option_rejected" => "候補を見送り",
    "planning_cost_link_created" => "費用を関連付け",
    "planning_cost_link_deleted" => "費用の関連付けを解除",
    "task_planning_link_created" => "タスクを関連付け",
    "task_planning_link_deleted" => "タスクの関連付けを解除",
    "music_detail_created" => "BGM情報を追加",
    "music_detail_updated" => "BGM情報を更新",
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
    "name" => "名前",
    "notes" => "メモ",
    "status" => "状態",
    "assignee" => "担当",
    "category" => "カテゴリ",
    "amount_yen" => "金額",
    "reference_price_yen" => "参考価格",
    "default_amount_yen" => "基準額",
    "unit_price_yen" => "単価",
    "quantity" => "数量",
    "capacity" => "定員",
    "occurred_on" => "日付",
    "kind" => "種類",
    "starts_on" => "開始日",
    "due_on" => "期限",
    "due_at" => "期限日時",
    "certainty" => "確度",
    "inclusion" => "集計",
    "direction" => "区分",
    "source_kind" => "情報元",
    "cost_mode" => "費用処理",
    "selected_option_id" => "採用候補",
    "budget_item_id" => "費用",
    "budget_item_title" => "費用",
    "created_budget_item_id" => "作成した費用",
    "excluded_budget_item_ids" => "除外した費用",
    "preserved_budget_item_ids" => "保持した費用",
    "task_id" => "タスク",
    "task_title" => "タスク",
    "planning_option_id" => "候補"
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
    return movement_subject_label if target_type == "MoneyMovement"
    return assignment_subject_label if target_type == "GiftAssignment"
    return guest_assignment_subject_label if target_type == "GuestGiftAssignment"
    return music_detail_subject_label if target_type == "MusicDetail"

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

  def changed_field_labels
    parsed_changes.filter_map do |field, values|
      field_label(field) if values[:before] != values[:after]
    end
  end

  private

  def movement_subject_label
    before_values = parsed_json(before)
    item_id = parsed_after["budget_item_id"] || before_values["budget_item_id"]
    kind = parsed_after["kind"] || before_values["kind"]
    item = wedding.budget_items.find_by(id: item_id)
    item ? "#{item.title}の#{MoneyMovement::KINDS.fetch(kind.to_s, "入出金")}" : "入出金履歴（削除済み）"
  end

  def assignment_subject_label
    household_id = parsed_after["household_id"] || parsed_json(before)["household_id"]
    wedding.households.find_by(id: household_id)&.name || "引き出物割当（削除済み）"
  end

  def guest_assignment_subject_label
    guest_id = parsed_after["guest_id"] || parsed_json(before)["guest_id"]
    wedding.guests.find_by(id: guest_id)&.name || "個人引き出物割当（削除済み）"
  end

  def music_detail_subject_label
    option_id = parsed_after["planning_option_id"] || parsed_json(before)["planning_option_id"]
    option = wedding.planning_options.find_by(id: option_id)
    option ? "#{option.title}のBGM" : "BGM情報（削除済み）"
  end

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
    when "MoneyMovement"
      return MoneyMovement::KINDS.fetch(value, value) if field == "kind"
      return "#{ActiveSupport::NumberHelper.number_to_delimited(value.to_i)}円" if field == "amount_yen"
    when "PlanningOption"
      return PlanningOption::STATUSES.fetch(value, value) if field == "status"
      return "#{ActiveSupport::NumberHelper.number_to_delimited(value.to_i)}円" if field == "reference_price_yen"
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
