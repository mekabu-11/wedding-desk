module CrossDocumentAi
  class Prepare
    def self.call(change_set, provider: Adapter.new)
      result = provider.call(change_set.document)
      operations = Array(result.fetch("operations"))
      ChangeSet.transaction do
        change_set.change_operations.delete_all
        operations.each do |operation|
          change_set.change_operations.create!(operation_key: operation.fetch("key"), action: operation.fetch("action"),
            entity_type: operation.fetch("entity_type"), target_id: operation["target_id"], expected_lock_version: operation["expected_lock_version"],
            attributes_data: operation.fetch("attributes"), depends_on_data: operation.fetch("depends_on"),
            evidence_data: operation.fetch("evidence"), uncertainties_data: operation.fetch("uncertainties"))
        end
        change_set.update!(summary: result.fetch("summary"), state: "pending", error: nil)
      end
      change_set
    end
  end
end
