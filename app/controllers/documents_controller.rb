class DocumentsController < ApplicationController
  before_action :set_document, only: %i[show destroy retry_analysis]
  rate_limit to: 20, within: 1.hour, only: %i[create retry_analysis]
  def index
    @source = params[:source].presence_in(Document::SOURCES.keys)
    @documents = current_wedding.documents.order(created_at: :desc)
    @documents = @documents.where(source_type: @source) if @source
    @page = [params[:page].to_i, 1].max
    @total_count = @documents.count
    @documents = @documents.offset((@page - 1) * 30).limit(30)
  end
  def new
    @document = Document.new(source_type: "email", direction: "incoming")
  end
  def create
    @document = current_wedding.documents.build(document_params)
    if @document.save
      start_analysis
    elsif @document.errors.of_kind?(:content_hash, :taken)
      existing = current_wedding.documents.find_by!(content_hash: @document.content_hash)
      redirect_to existing, notice: "同じ本文の資料は登録済みです。"
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to current_wedding.documents.find_by!(content_hash: @document.content_hash), notice: "登録済みの資料を開きました。"
  end
  def show
    @run = @document.latest_run
    @candidates = @document.candidates.order(:id).includes(:task)
  end
  def retry_analysis
    start_analysis
  end
  def sample
    @document = current_wedding.documents.find_by(sample: true)
    if @document
      redirect_to @document, notice: "登録済みのサンプルを開きました。"
    else
      @document = current_wedding.documents.create!(title: "式場からの連絡 — サンプル", original_text: Analysis::Sample::TEXT,
        source_type: "email", direction: "incoming", occurred_at: Time.zone.local(2026, 9, 6, 10), sample: true)
      start_analysis
    end
  end
  def destroy
    unless params[:confirm_delete] == "1"
      return redirect_to @document, alert: "削除の影響を確認してチェックしてください。"
    end
    @document.with_lock { @document.destroy! }
    redirect_to documents_path, notice: "資料を削除しました。登録済みのタスクは残ります。", status: :see_other
  end
  private
  def start_analysis
    Analysis::Start.call(@document)
    redirect_to @document, notice: "資料を保存しました。解析結果をお待ちください。"
  rescue Analysis::Error => error
    redirect_to @document, alert: helpers.analysis_error(error.code)
  end
  def set_document
    @document = current_wedding.documents.find(params[:id])
  end
  def document_params
    params.require(:document).permit(:title, :original_text, :source_type, :direction, :occurred_at)
  end
end
