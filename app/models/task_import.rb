class TaskImport < ApplicationRecord
  belongs_to :wedding
  encrypts :rows
  serialize :rows, coder: JSON
  validates :status, inclusion: { in: %w[pending committed] }
  validates :digest, presence: true
  validates :rows, presence: true
end
