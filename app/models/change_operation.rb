class ChangeOperation < ApplicationRecord
  ACTIONS = %w[create update link].freeze
  STATES = %w[pending applied failed].freeze
  ENTITY_TYPES = %w[Task Guest Household PlanningItem PlanningOption MusicDetail GiftSet GiftAssignment GuestGiftAssignment BudgetItem MoneyMovement].freeze
  LINK_ENTITY_TYPES = %w[SourceLink PlanningCostLink TaskPlanningLink].freeze
  ALL_ENTITY_TYPES = (ENTITY_TYPES + LINK_ENTITY_TYPES).freeze
  FORBIDDEN_ATTRIBUTES = %w[id wedding_id user_id lock_version candidate_id document_id created_at updated_at].freeze
  ATTRIBUTE_ALLOWLIST = {
    "Task" => %w[_key title description assignee starts_on due_on due_at category status origin source_key],
    "Guest" => %w[_key name household_id household_key seating_table_id seating_table_key side relationship gender age_group attendance invitation_status allergies notes roles],
    "Household" => %w[_key code name notes cash_gift_rule_id],
    "PlanningItem" => %w[_key title category notes position],
    "PlanningOption" => %w[_key title description status reference_price_yen planning_item_id planning_item_key],
    "MusicDetail" => %w[_key wish_track_a wish_track_b selected_track artist start_offset_seconds original_text scene planning_option_id planning_option_key],
    "GiftSet" => %w[_key name notes],
    "GiftAssignment" => %w[_key household_id household_key gift_set_id gift_set_key quantity included],
    "GuestGiftAssignment" => %w[_key guest_id guest_key gift_set_id gift_set_key quantity included],
    "BudgetItem" => %w[direction category title amount_yen certainty inclusion calculation_mode quantity_basis unit_price manual_quantity tax_basis tax_rate rounding source_kind source_id],
    "MoneyMovement" => %w[_key occurred_on kind amount_yen note budget_item_id budget_item_key]
  }.freeze
  LINK_ATTRIBUTE_ALLOWLIST = {
    "SourceLink" => %w[target_type target_id target_key attachment_id page quote region],
    "PlanningCostLink" => %w[planning_item_id planning_item_key budget_item_id budget_item_key],
    "TaskPlanningLink" => %w[task_id task_key planning_item_id planning_item_key]
  }.freeze
  ENUMS = {
    ["Task", "assignee"] => Task::ASSIGNEES.keys, ["Task", "status"] => Task::STATUSES.keys, ["Task", "category"] => Task::CATEGORIES.keys,
    ["Guest", "side"] => Guest::SIDES.keys, ["Guest", "age_group"] => Guest::AGE_GROUPS.keys, ["Guest", "attendance"] => Guest::ATTENDANCES.keys,
    ["Guest", "gender"] => Guest::GENDERS.keys, ["Guest", "invitation_status"] => Guest::INVITATION_STATUSES.keys,
    ["BudgetItem", "direction"] => BudgetItem::DIRECTIONS.keys, ["BudgetItem", "certainty"] => BudgetItem::CERTAINTIES.keys,
    ["BudgetItem", "inclusion"] => BudgetItem::INCLUSIONS.keys, ["BudgetItem", "calculation_mode"] => BudgetItem::CALCULATION_MODES.keys,
    ["BudgetItem", "tax_basis"] => BudgetItem::TAX_BASES.keys, ["BudgetItem", "rounding"] => %w[floor round ceil]
  }.freeze

  belongs_to :change_set

  encrypts :attributes_data, :before_data, :after_data, :evidence_data, :uncertainties_data, :depends_on_data, :error
  serialize :attributes_data, coder: JSON
  serialize :before_data, coder: JSON
  serialize :after_data, coder: JSON
  serialize :evidence_data, coder: JSON
  serialize :uncertainties_data, coder: JSON
  serialize :depends_on_data, coder: JSON

  validates :operation_key, presence: true, uniqueness: { scope: :change_set_id }
  validates :action, inclusion: { in: ACTIONS }
  validates :entity_type, inclusion: { in: ALL_ENTITY_TYPES }
  validates :state, inclusion: { in: STATES }
  validate :contract_attributes
  validate :update_requires_lock_version

  def self.allowlist_attribute_issues
    (ATTRIBUTE_ALLOWLIST.merge(LINK_ATTRIBUTE_ALLOWLIST)).flat_map do |entity_type, attributes|
      klass = entity_type.constantize
      attributes.reject { |attribute| attribute == "_key" || attribute.end_with?("_key") || klass.column_names.include?(attribute) }
        .map { |attribute| [entity_type, attribute] }
    end
  end

  def attributes_hash
    attributes_data.is_a?(Hash) ? attributes_data.stringify_keys : {}
  end

  def evidence
    evidence_data.is_a?(Array) ? evidence_data : []
  end

  private

  def contract_attributes
    keys = attributes_hash.keys
    forbidden = keys & FORBIDDEN_ATTRIBUTES
    errors.add(:attributes_data, "管理項目は指定できません") if forbidden.any?
    allowlist = action == "link" ? LINK_ATTRIBUTE_ALLOWLIST.fetch(entity_type, []) : ATTRIBUTE_ALLOWLIST.fetch(entity_type, [])
    errors.add(:action, "リンク対象以外ではlinkを使えません") if action == "link" && !LINK_ENTITY_TYPES.include?(entity_type)
    errors.add(:action, "link対象はlink操作だけです") if action != "link" && LINK_ENTITY_TYPES.include?(entity_type)
    errors.add(:attributes_data, "許可されていない項目があります") unless (keys - allowlist).empty?
    errors.add(:attributes_data, "項目数が多すぎます") if keys.size > 30
    errors.add(:evidence_data, "根拠の形式が不正です") unless evidence.all? { |entry| entry.is_a?(Hash) }
    errors.add(:depends_on_data, "依存関係の形式が不正です") unless depends_on_data.blank? || depends_on_data.is_a?(Array)
    errors.add(:attributes_data, "AIから採用状態は設定できません") if attributes_hash["status"] == "selected"
    errors.add(:attributes_data, "AIから確定金額は設定できません") if attributes_hash["certainty"] == "confirmed"
    errors.add(:entity_type, "入出金履歴はAI候補にできません") if entity_type == "MoneyMovement"
    attributes_hash.each do |key, value|
      allowed = ENUMS[[entity_type, key]]
      errors.add(:attributes_data, "値が不正です") if allowed && !Array(value).all? { |entry| allowed.include?(entry.to_s) }
      errors.add(:attributes_data, "文字数が上限を超えています") if value.is_a?(String) && value.length > 3000
    end
  end

  def update_requires_lock_version
    errors.add(:expected_lock_version, "更新には版番号が必要です") if action == "update" && expected_lock_version.nil?
  end
end
