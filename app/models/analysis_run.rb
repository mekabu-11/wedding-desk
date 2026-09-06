class AnalysisRun < ApplicationRecord
  belongs_to :document
  has_many :candidates, dependent: :destroy
  encrypts :summary
  validates :status, inclusion: { in: %w[pending processing completed failed] }
  validates :provider, inclusion: { in: %w[openai sample] }
  def active?
    %w[pending processing].include?(status)
  end
end
