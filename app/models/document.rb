require "digest"
class Document < ApplicationRecord
  SOURCES = { "email" => "メール", "line" => "LINE", "meeting" => "打ち合わせ", "other" => "その他" }.freeze
  DIRECTIONS = { "incoming" => "相手から受信", "outgoing" => "自分から送信", "memo" => "メモ", "mixed" => "複数のやり取り", "unknown" => "不明" }.freeze
  belongs_to :wedding
  has_many :analysis_runs, dependent: :destroy
  has_many :candidates, dependent: :destroy
  encrypts :original_text
  before_validation :prepare_content, on: :create
  validates :title, presence: true, length: { maximum: 150 }
  validates :original_text, presence: true, length: { maximum: 30_000 }
  validates :source_type, inclusion: { in: SOURCES.keys }
  validates :direction, inclusion: { in: DIRECTIONS.keys }
  validates :content_hash, uniqueness: { scope: :wedding_id }
  validate :valid_occurred_at
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
  def prepare_content
    self.original_text = original_text.to_s.gsub("\r\n", "\n").strip
    self.title = original_text.lines.first.to_s.strip.truncate(70) if title.blank?
    self.content_hash = Digest::SHA256.hexdigest(original_text)
  end
end
