class SpreadsheetImportRow < ApplicationRecord
  STATES = %w[pending ready skipped conflict invalid imported].freeze

  belongs_to :wedding
  belongs_to :spreadsheet_import_batch

  encrypts :original_data, :warnings, :error
  encrypts :mapping_label
  serialize :original_data, coder: JSON
  serialize :warnings, coder: JSON

  validates :row_kind, :sheet_name, :source_key, presence: true
  validates :row_number, numericality: { only_integer: true, greater_than: 0 }
  validates :state, inclusion: { in: STATES }
  validate :same_wedding

  private

  def same_wedding
    errors.add(:spreadsheet_import_batch, "結婚式が一致しません") if spreadsheet_import_batch && spreadsheet_import_batch.wedding_id != wedding_id
  end
end
