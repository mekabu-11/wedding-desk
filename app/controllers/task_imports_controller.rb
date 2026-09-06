class TaskImportsController < ApplicationController
  before_action :set_batch, only: %i[show update]
  def new
    @imports = current_wedding.task_imports.order(created_at: :desc).limit(10)
  end
  def create
    file = params[:file]
    raise ImportTasks::Invalid, "移行用JSONファイルを選んでください。" unless file.respond_to?(:read)
    @batch = ImportTasks.prepare(current_wedding, file.read(ImportTasks::MAX_BYTES + 1))
    redirect_to task_import_path(@batch), status: :see_other
  rescue ImportTasks::Invalid => e
    redirect_to new_task_import_path, alert: e.message, status: :see_other
  end
  def show
    @labels = @batch.rows.map { |r| r["assignee_raw"].to_s }.uniq
    @existing_keys = current_wedding.tasks.where(source_key: @batch.rows.map { |r| r["source_key"] }).pluck(:source_key)
  end
  def update
    unless params[:confirmed] == "1"
      return redirect_to task_import_path(@batch), alert: "取り込み内容を確認してチェックしてください。", status: :see_other
    end
    labels = @batch.rows.map { |r| r["assignee_raw"].to_s }.uniq
    submitted = params[:mapping].is_a?(ActionController::Parameters) ? params[:mapping] : {}
    mapping = labels.each_with_index.to_h { |label, i| [label, submitted[i.to_s]] }
    ImportTasks.commit(@batch, mapping)
    redirect_to task_import_path(@batch), status: :see_other
  rescue ImportTasks::Invalid, ActiveRecord::RecordInvalid
    redirect_to task_import_path(@batch), alert: "取り込みできませんでした。担当と入力内容を確認してください。追加内容は保存されていません。", status: :see_other
  end
  private
  def set_batch
    @batch = current_wedding.task_imports.find(params[:id])
  end
end
