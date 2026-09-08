class ChangeSet < ApplicationRecord
  STATES = %w[pending applied failed].freeze

  belongs_to :wedding
  belongs_to :document
  belongs_to :actor, class_name: "User", optional: true
  has_many :change_operations, dependent: :destroy

  encrypts :summary, :error
  validates :state, inclusion: { in: STATES }
  validates :operation_key, presence: true, uniqueness: { scope: :wedding_id }
  validate :document_belongs_to_wedding

  private

  def document_belongs_to_wedding
    errors.add(:document, "結婚式が一致しません") if document && document.wedding_id != wedding_id
  end
end
