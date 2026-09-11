require "digest"
require "base64"
require "open3"
class Document < ApplicationRecord
  SOURCES = {
    "email" => "メール", "line" => "LINE", "meeting" => "打ち合わせ",
    "text" => "文章", "photo" => "写真・スキャン", "file" => "PDF・ファイル", "other" => "その他"
  }.freeze
  SOURCE_FILTERS = {
    "text" => { label: "文章", types: %w[text email line] },
    "photo" => { label: "写真・スキャン", types: %w[photo] },
    "file" => { label: "PDF・ファイル", types: %w[file] },
    "meeting" => { label: "打ち合わせ", types: %w[meeting] },
    "other" => { label: "その他", types: %w[other] }
  }.freeze
  DIRECTIONS = { "incoming" => "相手から受信", "outgoing" => "自分から送信", "memo" => "メモ", "mixed" => "複数のやり取り", "unknown" => "不明" }.freeze
  belongs_to :wedding
  has_many_attached :attachments, dependent: :purge_later
  has_many :analysis_runs, dependent: :destroy
  has_many :candidates, dependent: :destroy
  has_many :source_links, dependent: :destroy
  has_many :change_sets, dependent: :destroy
  before_destroy :detach_tasks_and_keep_source, prepend: true
  before_destroy :record_deletion_event, prepend: true
  encrypts :original_text
  encrypts :memo
  before_validation :infer_input_metadata
  before_validation :prepare_content
  validates :title, presence: true, length: { maximum: 150 }
  validates :original_text, length: { maximum: 30_000 }, allow_nil: true
  validates :source_type, inclusion: { in: SOURCES.keys }
  validates :direction, inclusion: { in: DIRECTIONS.keys }
  validates :content_hash, uniqueness: { scope: :wedding_id }
  validate :valid_occurred_at
  validate :content_or_attachment
  validate :valid_attachments

  ACCEPTED_ATTACHMENT_TYPES = %w[image/jpeg image/png image/webp image/heic image/heif application/pdf].freeze
  MAX_ATTACHMENT_BYTES = 20.megabytes
  MAX_ATTACHMENTS = 10
  MAX_TOTAL_ATTACHMENT_BYTES = 50.megabytes
  MAX_IMAGE_PIXELS = 40_000_000
  MAX_PDF_PAGES = 20

  def self.storage_configured?
    return true unless Rails.env.production?
    return true unless Rails.configuration.active_storage.service.to_sym == :supabase

    %w[SUPABASE_STORAGE_ENDPOINT SUPABASE_STORAGE_BUCKET SUPABASE_STORAGE_ACCESS_KEY_ID SUPABASE_STORAGE_SECRET_ACCESS_KEY].all? { |key| ENV[key].present? }
  end

  def self.source_filter_key(value)
    SOURCE_FILTERS.keys.find { |key| key == value || SOURCE_FILTERS.fetch(key)[:types].include?(value) }
  end

  def attachment_inputs
    pending = attachment_changes["attachments"] if respond_to?(:attachment_changes)
    attachables = pending.respond_to?(:attachables) ? pending.attachables : []
    attachables.presence || attachments.attachments
  end

  def attachment_content_changed?
    new_record? || attachment_changes["attachments"].present?
  end

  def content_available?
    original_text.present? || attachments.attached? || attachment_inputs.present?
  end
  def valid_occurred_at
    raw = occurred_at_before_type_cast
    return if raw.blank?
    errors.add(:occurred_at, "を正しい日時で入力してください") if occurred_at.nil?
    if raw.is_a?(String)
      begin
        Date.iso8601(raw.split("T").first)
      rescue Date::Error
        errors.add(:occurred_at, "を正しい日付で入力してください")
      end
    end
  end
  def latest_run
    analysis_runs.order(id: :desc).first
  end
  def pending_candidates
    candidates.where(review_status: "pending")
  end
  def retryable?
    run = latest_run
    !run || %w[failed completed].include?(run.status) || run.updated_at < 5.minutes.ago
  end
  private

  def infer_input_metadata
    self.direction = "unknown" if direction.blank?
    return if source_type.present?

    inputs = attachment_inputs
    self.source_type = if inputs.blank?
      "text"
    elsif inputs.all? { |input| attachment_content_type(input).to_s.start_with?("image/") }
      "photo"
    else
      "file"
    end
  end

  def detach_tasks_and_keep_source
    candidate_tasks = candidates.includes(:task).filter_map(&:task)
    linked_task_ids = source_links.where(target_type: "Task").pluck(:target_id)
    wedding.tasks.where(id: (candidate_tasks.map(&:id) + linked_task_ids).uniq).includes(:candidate).each do |task|
      candidate = task.candidate
      SourceLink.create!(wedding: wedding, document: self, target_type: "Task", target_id: task.id,
        quote: candidate&.evidence&.fetch("quote", nil)) unless SourceLink.exists?(document: self, target_type: "Task", target_id: task.id)
      details = task.source_details.is_a?(Hash) ? task.source_details.deep_dup : {}
      details.merge!(
        "document_id" => id,
        "title" => title,
        "source_type" => source_type,
        "source_title" => title,
        "source_occurred_at" => occurred_at&.iso8601,
        "source_deleted_at" => Time.current.iso8601
      )
      task.update!(candidate: nil, source_details: details)
    end
  end

  def record_deletion_event
    ChangeEvent.record!(wedding: wedding, target: self, action: "document_deleted", source: "document_deleted",
      after: { title: title, source_type: source_type }.to_json) if defined?(ChangeEvent) && wedding
  end

  def prepare_content
    if new_record? || will_save_change_to_original_text?
      self.original_text = original_text.to_s.gsub("\r\n", "\n").strip
      self.original_text = nil if original_text.blank?
    end
    self.title = if title.blank? && original_text.present?
      original_text.lines.first.to_s.strip.truncate(70)
    elsif title.blank?
      attachment_inputs.first.respond_to?(:original_filename) ? attachment_inputs.first.original_filename.to_s.truncate(70) : "添付資料"
    else
      title
    end
    if new_record? || will_save_change_to_original_text? || attachment_content_changed?
      self.content_hash = Digest::SHA256.hexdigest([original_text, attachment_checksums.sort].join("\0"))
    end
  end

  def content_or_attachment
    errors.add(:base, "本文または添付ファイルを1つ以上入力してください") unless content_available?
  end

  def valid_attachments
    inputs = attachment_inputs
    return if inputs.blank?
    return unless attachment_content_changed?
    errors.add(:attachments, "本番の添付保存設定が未完了です") unless self.class.storage_configured?
    errors.add(:attachments, "添付は10個までです") if inputs.size > MAX_ATTACHMENTS
    total = inputs.sum { |input| attachment_size(input) }
    errors.add(:attachments, "添付の合計は50MBまでです") if total > MAX_TOTAL_ATTACHMENT_BYTES
    inputs.each do |input|
      content_type = attachment_content_type(input)
      size = attachment_size(input)
      errors.add(:attachments, "対応していないファイル形式です") unless ACCEPTED_ATTACHMENT_TYPES.include?(content_type)
      errors.add(:attachments, "1ファイル20MBまでです") if size > MAX_ATTACHMENT_BYTES
      errors.add(:attachments, "SVGは受け付けていません") if content_type == "image/svg+xml" || input.to_s.downcase.end_with?(".svg")
      validate_decoded_attachment(input, content_type)
    end
  end

  def attachment_content_type(input)
    return input.content_type if input.respond_to?(:content_type)
    return input.blob.content_type if input.respond_to?(:blob)
    Marcel::MimeType.for(input.respond_to?(:io) ? input.io : input)
  end

  def attachment_size(input)
    return input.byte_size if input.respond_to?(:byte_size)
    return input.size if input.respond_to?(:size)
    input.respond_to?(:io) && input.io.respond_to?(:size) ? input.io.size : 0
  end

  def attachment_checksums
    attachment_inputs.filter_map do |input|
      if input.respond_to?(:blob)
        next input.blob.checksum
      end
      io = input.respond_to?(:io) ? input.io : input.respond_to?(:path) ? File.open(input.path, "rb") : input
      next unless io.respond_to?(:read)
      position = io.pos if io.respond_to?(:pos)
      io.rewind if io.respond_to?(:rewind)
      checksum = Digest::MD5.base64digest(io.read.to_s)
      io.seek(position) if position && io.respond_to?(:seek)
      io.close if io.is_a?(File)
      checksum
    end
  end

  def validate_decoded_attachment(input, content_type)
    return if input.respond_to?(:blob) && !input.blob.new_record? && !input.blob.changed?
    io = input.respond_to?(:io) ? input.io : nil
    path = input.path if input.respond_to?(:path) && input.path.present?
    return unless io || path
    Tempfile.create(["wedding-desk-attachment", File.extname(input.respond_to?(:original_filename) ? input.original_filename.to_s : "")]) do |file|
      unless path
        io.rewind if io.respond_to?(:rewind)
        file.write(io.read.to_s)
        file.flush
        path = file.path
      end
      if content_type == "application/pdf"
        output, = Open3.capture2("pdfinfo", path)
        errors.add(:attachments, "PDFを読み取れません。暗号化PDFは利用できません") unless output.include?("Pages:") && !output.match?(/Encrypted:\s+yes/i)
        pages = output[/^Pages:\s+(\d+)/, 1].to_i
        errors.add(:attachments, "PDFは20ページまでです") if pages > MAX_PDF_PAGES
      elsif content_type.start_with?("image/")
        width, = Open3.capture2("vipsheader", "-f", "width", path)
        height, = Open3.capture2("vipsheader", "-f", "height", path)
        pixels = width.to_i * height.to_i
        errors.add(:attachments, "画像は40メガピクセルまでです") if pixels <= 0 || pixels > MAX_IMAGE_PIXELS
      end
    end
  rescue StandardError
    errors.add(:attachments, "添付ファイルを読み取れません。内容と形式を確認してください")
  end
end
