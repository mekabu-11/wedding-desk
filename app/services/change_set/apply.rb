class ChangeSet
  class Apply
    class Conflict < StandardError; end
    class InvalidEvidence < StandardError; end
    class InvalidOperation < StandardError; end

    def self.call(change_set:, operation_ids:)
      new(change_set, operation_ids).call
    end

    def initialize(change_set, operation_ids)
      @change_set = change_set
      @wedding = change_set.wedding
      @operations = change_set.change_operations.where(id: operation_ids).order(:id)
      @created = {}
    end

    def call
      raise InvalidOperation, "反映対象を選択してください" if @operations.empty?
      return @change_set if @change_set.state == "applied"
      validate_dependencies!
      ActiveRecord::Base.transaction do
        @operations.each { |operation| apply_operation!(operation) }
        @change_set.update!(state: "applied", error: nil)
      end
      @change_set
    rescue ActiveRecord::StaleObjectError, Conflict => error
      @change_set.update_columns(state: "failed", error: "競合があるため反映していません")
      raise Conflict, error.message
    rescue InvalidOperation, InvalidEvidence => error
      @change_set.update_columns(state: "failed", error: error.message)
      raise
    rescue ActiveRecord::RecordNotUnique
      @change_set.update_columns(state: "failed", error: "同じ変更がすでに反映されています")
      raise InvalidOperation, "同じ変更がすでに反映されています"
    end

    private

    def validate_dependencies!
      selected = @operations.map(&:operation_key)
      @operations.each do |operation|
        missing = Array(operation.depends_on_data).map(&:to_s) - selected
        raise InvalidOperation, "依存する候補も選択してください" if missing.any?
        validate_evidence!(operation)
      end
      @operations = topological_order(@operations)
    end

    def topological_order(operations)
      remaining = operations.dup
      ordered = []
      until remaining.empty?
        ready = remaining.select do |operation|
          Array(operation.depends_on_data).map(&:to_s).all? do |dependency|
            ordered.any? { |applied| applied.operation_key == dependency }
          end
        end
        raise InvalidOperation, "依存関係が循環しています" if ready.empty?

        ordered.concat(ready)
        remaining -= ready
      end
      ordered
    end

    def validate_evidence!(operation)
      entries = operation.evidence
      if %w[Guest Household BudgetItem MoneyMovement].include?(operation.entity_type) && entries.empty?
        raise InvalidEvidence, "重要な変更には根拠が必要です"
      end
      entries.each do |entry|
        document = @wedding.documents.find_by(id: entry["document_id"] || entry[:document_id])
        raise InvalidEvidence, "根拠の資料が結婚式に属していません" unless document
        quote = entry["quote"] || entry[:quote]
        raise InvalidEvidence, "本文の引用が一致しません" if quote.present? && !document.original_text.to_s.include?(quote)
        attachment_id = entry["attachment_id"] || entry[:attachment_id]
        if attachment_id.present? && !document.attachments.attachments.exists?(id: attachment_id)
          raise InvalidEvidence, "画像根拠が資料に属していません"
        end
        if attachment_id.present? && quote.blank? && operation.entity_type == "Guest" && operation.attributes_hash.key?("attendance")
          raise InvalidEvidence, "画像だけから出欠は確定できません"
        end
      end
    end

    def apply_operation!(operation)
      attrs = operation.attributes_hash
      reject_unsafe_ai_operation!(operation, attrs)
      case operation.action
      when "create" then create_record!(operation, attrs)
      when "update" then update_record!(operation, attrs)
      when "link" then link_record!(operation, attrs)
      else raise InvalidOperation, "未対応の操作です"
      end
      operation.update!(state: "applied", error: nil)
    end

    def reject_unsafe_ai_operation!(operation, attrs)
      raise InvalidOperation, "AIから支払い履歴は作成できません" if operation.entity_type == "MoneyMovement"
      raise InvalidOperation, "AIから採用状態は設定できません" if attrs["status"] == "selected"
      raise InvalidOperation, "AIから確定金額は設定できません" if attrs["certainty"] == "confirmed"
      raise InvalidOperation, "削除操作は利用できません" if operation.action == "delete"
    end

    def create_record!(operation, attrs)
      klass = operation.entity_type.constantize
      key = attrs["_key"]
      attrs = resolve_references(operation.entity_type, attrs.except("_key"))
      record = case operation.entity_type
      when "Task", "Guest", "Household", "PlanningItem", "PlanningOption", "GiftSet", "GiftAssignment", "BudgetItem"
        @wedding.public_send(klass.model_name.collection).new(attrs)
      when "MusicDetail"
        option = @wedding.planning_options.find(attrs.delete("planning_option_id"))
        option.build_music_detail(attrs.merge(wedding: @wedding))
      else
        raise InvalidOperation, "作成対象が不正です"
      end
      record.save!
      budget_item = GiftAssignmentBudgetItemSync.call!(record) if record.is_a?(GiftAssignment)
      @created[operation.operation_key] = record
      @created[key.to_s] = record if key.present?
      record_change_event!(record, {}, attrs)
      create_source_links!(record, operation)
      if budget_item
        record_change_event!(budget_item, {}, budget_item.attributes.slice("amount_yen", "title", "inclusion", "source_kind", "source_id"))
        create_source_links!(budget_item, operation)
      end
    end

    def update_record!(operation, attrs)
      record = scoped_record(operation)
      record.with_lock do
        raise Conflict, "対象が変更されています" if record.lock_version != operation.expected_lock_version
        resolved = resolve_references(operation.entity_type, attrs)
        before = record.attributes.slice(*resolved.keys)
        record.update!(resolved)
        record_change_event!(record, before, resolved)
        create_source_links!(record, operation)
      end
    end

    def record_change_event!(record, before, after)
      ChangeEvent.record!(wedding: @wedding, target: record, action: "change_set_applied",
        before: before.to_json, after: after.to_json, source: "change_set", actor: @change_set.actor)
    end

    def create_source_links!(record, operation)
      if record.is_a?(Task) && record.origin == "ai" && operation.evidence.empty?
        raise InvalidEvidence, "AIタスクには根拠が必要です"
      end

      operation.evidence.each do |entry|
        entry = entry.stringify_keys
        document = @wedding.documents.find_by(id: entry["document_id"])
        raise InvalidEvidence, "根拠の資料が結婚式に属していません" unless document

        @wedding.source_links.create!(document: document, target_type: record.class.name, target_id: record.id,
          attachment_id: entry["attachment_id"], page: entry["page"], quote: entry["quote"], region: entry["region"])
      end
    end

    def link_record!(operation, attrs)
      attrs = resolve_references(operation.entity_type, attrs)
      case operation.entity_type
      when "SourceLink"
        @wedding.source_links.create!(attrs.merge(document: @change_set.document))
      when "PlanningCostLink", "TaskPlanningLink"
        @wedding.public_send(operation.entity_type.underscore.pluralize).create!(attrs)
      else
        raise InvalidOperation, "リンク対象が不正です"
      end
    end

    def resolve_references(_entity_type, attrs)
      attrs = attrs.stringify_keys
      mappings = {
        "household_key" => "household_id", "seating_table_key" => "seating_table_id", "planning_item_key" => "planning_item_id",
        "planning_option_key" => "planning_option_id", "gift_set_key" => "gift_set_id", "budget_item_key" => "budget_item_id",
        "task_key" => "task_id", "target_key" => "target_id"
      }
      mappings.each do |key, foreign_key|
        next unless attrs[key].present?
        record = @created[attrs.delete(key).to_s]
        raise InvalidOperation, "作成した候補を参照できません" unless record
        attrs[foreign_key] = record.id
      end
      attrs
    end

    def scoped_record(operation)
      klass = operation.entity_type.constantize
      return @created[operation.target_id.to_s] if @created.key?(operation.target_id.to_s)
      return @wedding.public_send(klass.model_name.collection).find(operation.target_id) if klass.reflect_on_association(:wedding)
      klass.find(operation.target_id)
    rescue ActiveRecord::RecordNotFound
      raise Conflict, "対象が見つかりません"
    end
  end
end
