class Candidate < ApplicationRecord
  belongs_to :document
  belongs_to :analysis_run
  has_one :task, dependent: :nullify
  encrypts :payload
  encrypts :evidence
  serialize :payload, coder: JSON
  serialize :evidence, coder: JSON
  validates :review_status, inclusion: { in: %w[pending accepted rejected] }
  validate :same_document
  def same_document
    errors.add(:analysis_run, "資料が一致しません") if analysis_run && analysis_run.document_id != document_id
  end
end
