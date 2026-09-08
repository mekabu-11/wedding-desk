class SpreadsheetImportsController < ApplicationController
  before_action :set_batch, only: %i[show update]

  def new
    @batches = current_wedding.spreadsheet_import_batches.order(created_at: :desc).limit(10)
  end

  def create
    files = params[:files].respond_to?(:to_ary) ? params[:files].to_ary : []
    @batch = SpreadsheetImport.prepare(current_wedding, files)
    redirect_to spreadsheet_import_path(@batch), status: :see_other
  rescue SpreadsheetImport::Invalid => error
    redirect_to new_spreadsheet_import_path, alert: error.message, status: :see_other
  end

  def show
    @rows = @batch.rows.order(:id)
    @labels = @rows.filter_map(&:mapping_label).uniq
  end

  def update
    unless params[:confirmed] == "1"
      return redirect_to spreadsheet_import_path(@batch), alert: "内容を確認してから反映してください。", status: :see_other
    end
    mapping = params[:mapping].respond_to?(:to_unsafe_h) ? params[:mapping].to_unsafe_h : {}
    SpreadsheetImport.commit(@batch, mapping, confirmed: true)
    redirect_to spreadsheet_import_path(@batch), status: :see_other
  rescue SpreadsheetImport::Invalid
    redirect_to spreadsheet_import_path(@batch), alert: "Excelを反映できませんでした。危険な行や担当の割り当てを確認してください。追加内容は保存されていません。", status: :see_other
  end

  private

  def set_batch
    @batch = current_wedding.spreadsheet_import_batches.find(params[:id])
  end
end
