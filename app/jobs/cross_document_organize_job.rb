class CrossDocumentOrganizeJob < ApplicationJob
  queue_as :default

  def perform(change_set_id)
    change_set = ChangeSet.find_by(id: change_set_id)
    return unless change_set && change_set.state == "pending"
    CrossDocumentAi::Prepare.call(change_set)
  rescue CrossDocumentAi::Error
    change_set&.update_columns(state: "failed", error: "AI整理の外部連携が設定されていません")
  rescue ActiveRecord::RecordInvalid
    change_set&.update_columns(state: "failed", error: "AIの候補形式を検証できませんでした")
  end
end
