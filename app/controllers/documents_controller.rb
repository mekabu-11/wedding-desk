class DocumentsController < ApplicationController
  before_action :set_document, only: %i[show destroy retry_analysis organize]
  rate_limit to: 20, within: 1.hour, only: %i[create retry_analysis]
  def index
    legacy_source = params[:source].to_s
    @media = Document.media_filter_key(params[:media].presence || (legacy_source if Document::MEDIA_FILTERS.key?(legacy_source)))
    @origin = Document.origin_filter_key(params[:origin].presence || (legacy_source if Document::ORIGIN_FILTERS.key?(legacy_source) && !Document::MEDIA_FILTERS.key?(legacy_source)))
    @direction = params[:direction].presence_in(Document::DIRECTIONS.keys)
    @documents = current_wedding.documents.order(created_at: :desc)
    @documents = @documents.where(source_type: Document::MEDIA_FILTERS.fetch(@media).fetch(:types)) if @media
    @documents = @documents.where(source_type: Document::ORIGIN_FILTERS.fetch(@origin).fetch(:types)) if @origin
    @documents = @documents.where(direction: @direction) if @direction
    @page = [params[:page].to_i, 1].max
    @total_count = @documents.count
    @documents = @documents.offset((@page - 1) * 30).limit(30)
  end
  def new
    @document = Document.new(direction: "unknown")
  end
  def create
    @document = current_wedding.documents.build(document_params)
    saved = ActiveRecord::Base.transaction do
      result = @document.save
      record_change!(@document, "document_created", after: change_snapshot(@document, :title, :source_type, :direction, :occurred_at)) if result
      result
    end
    if saved
      params[:organize] == "1" ? start_cross_document_organize : redirect_to(@document, notice: "資料を保存しました。")
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
    @change_sets = @document.change_sets.order(created_at: :desc).limit(10)
  end
  def retry_analysis
    start_analysis
  end
  def organize
    start_cross_document_organize
  end
  def sample
    @document = current_wedding.documents.find_by(sample: true)
    if @document
      redirect_to @document, notice: "登録済みのサンプルを開きました。"
    else
      @document = current_wedding.documents.create!(title: "式場からの連絡 — サンプル", original_text: Analysis::Sample::TEXT,
        source_type: "email", direction: "incoming", occurred_at: Time.zone.local(2026, 9, 6, 10), sample: true)
      record_change!(@document, "document_created", after: change_snapshot(@document, :title, :source_type, :direction, :occurred_at), source: "sample")
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
    params.require(:document).permit(:title, :original_text, :memo, :source_type, :direction, :occurred_at, attachments: [])
  end
  def start_cross_document_organize
    key = Digest::SHA256.hexdigest([@document.id, @document.content_hash].join(":"))
    change_set = @document.change_sets.find_or_create_by!(wedding: current_wedding, operation_key: key) do |set|
      set.actor = current_user
    end
    CrossDocumentOrganizeJob.perform_later(change_set.id) if change_set.pending?
    redirect_to change_set_path(change_set), notice: "AI整理を開始しました。内容を確認してから反映してください。"
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to @document, alert: "AI整理を開始できませんでした。資料を確認してください。"
  end
end
