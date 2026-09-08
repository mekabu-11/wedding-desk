class SpreadsheetImportBatch < ApplicationRecord
  STATES = %w[pending committed failed].freeze

  belongs_to :wedding
  has_many :rows, class_name: "SpreadsheetImportRow", dependent: :destroy

  encrypts :source_metadata, :warnings
  serialize :source_metadata, coder: JSON
  serialize :warnings, coder: JSON

  validates :digest, presence: true, uniqueness: { scope: :wedding_id }
  validates :mapping_version, presence: true
  validates :state, inclusion: { in: STATES }
end
