class SourceLink < ApplicationRecord
  TARGET_TYPES = %w[Task Guest Household PlanningItem PlanningOption MusicDetail GiftSet GiftAssignment GuestGiftAssignment BudgetItem MoneyMovement].freeze

  belongs_to :wedding
  belongs_to :document
  belongs_to :attachment, class_name: "ActiveStorage::Attachment", optional: true

  validates :target_type, inclusion: { in: TARGET_TYPES }
  validates :target_id, numericality: { only_integer: true, greater_than: 0 }
  validates :page, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :target_belongs_to_wedding
  validate :attachment_belongs_to_document
  validate :document_belongs_to_wedding

  private

  def target_belongs_to_wedding
    target = target_type.safe_constantize&.find_by(id: target_id)
    errors.add(:target_id, "結婚式が一致しません") if target.nil? || target.wedding_id != wedding_id
  end

  def attachment_belongs_to_document
    errors.add(:attachment_id, "資料の添付ではありません") if attachment && attachment.record_type != "Document"
    errors.add(:attachment_id, "資料の添付ではありません") if attachment && attachment.record_id != document_id
  end

  def document_belongs_to_wedding
    errors.add(:document, "結婚式が一致しません") if document && document.wedding_id != wedding_id
  end
end
