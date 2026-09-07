require "digest"

class ImportTasks
  class Invalid < StandardError; end
  MAX_BYTES = 2.megabytes
  MAX_ROWS = 500
  CATEGORY_MAP = { "招待状・招待客関連" => "invitation", "sircle登録" => "guest",
    "ペーパーアイテム" => "invitation", "料理・飲み物" => "food", "引出物・ギフト" => "gift",
    "衣装" => "other", "写真" => "photo", "映像" => "movie", "音楽" => "music",
    "その他" => "other" }.freeze

  def self.prepare(wedding, text)
    raise Invalid, "ファイルは2MB以下にしてください。" if text.bytesize > MAX_BYTES
    data = JSON.parse(text)
    raise Invalid, "移行用JSON（形式1）を選んでください。" unless data.is_a?(Hash) && data["format_version"] == 1 && data["groups"].is_a?(Hash)
    rows = data["groups"]["tasks"]
    raise Invalid, "タスクは1〜500件で取り込んでください。" unless rows.is_a?(Array) && rows.size.between?(1, MAX_ROWS)
    rows = rows.each_with_index.map { |row, index| normalize(row, index + 1) }
    raise Invalid, "同じ出典行が複数あります。" unless rows.map { |r| r["source_key"] }.uniq.size == rows.size
    digest = Digest::SHA256.hexdigest(JSON.generate(rows))
    wedding.task_imports.create_or_find_by!(digest: digest) { |batch| batch.rows = rows }
  rescue JSON::ParserError, EncodingError
    raise Invalid, "JSONを読み込めません。移行用JSONを選んでください。"
  end

  def self.normalize(row, number)
    raise Invalid, "#{number}件目の形式が正しくありません。" unless row.is_a?(Hash)
    allowed = %w[title notes starts_on due_on category_raw assignee_raw status_raw source_file source_sheet source_row source_sha256]
    item = row.slice(*allowed)
    %w[title notes category_raw assignee_raw status_raw source_file source_sheet source_sha256 starts_on due_on].each do |key|
      raise Invalid, "#{number}件目の#{key}は文字列で指定してください。" unless item[key].nil? || item[key].is_a?(String)
    end
    raise Invalid, "#{number}件目の出典情報が不足しています。" unless item["source_sha256"].to_s.match?(/\A[0-9a-f]{64}\z/) && item["source_row"].is_a?(Integer) && item["source_row"].positive? && item["source_sheet"].present? && item["source_file"].present?
    raise Invalid, "#{number}件目の文字数が上限を超えています。" if %w[category_raw assignee_raw source_file source_sheet].any? { |k| item[k].to_s.length > 255 }
    %w[starts_on due_on].each do |key|
      next item[key] = nil if item[key].blank?
      raw = item[key]
      raise Invalid, "#{number}件目の日付は日付のみで指定してください。" unless raw.match?(/\A\d{4}-\d{2}-\d{2}(T00:00:00)?\z/)
      item[key] = Date.iso8601(raw[0,10]).iso8601
    end
    item["status"] = Task::STATUSES.key(item["status_raw"])
    raise Invalid, "#{number}件目の状態を確認してください。" unless item["status"]
    item["category"] = CATEGORY_MAP.fetch(item["category_raw"], "other")
    item["source_key"] = Digest::SHA256.hexdigest([item["source_sha256"], item["source_sheet"], item["source_row"]].to_json)
    task = Task.new(attributes(item, {}))
    # Check field validators without requiring a persisted Wedding.
    task.valid?
    errors = task.errors.reject { |error| error.attribute == :wedding }
    raise Invalid, "#{number}件目：#{errors.map(&:full_message).join('、')}" if errors.any?
    item
  rescue Date::Error
    raise Invalid, "#{number}件目に存在しない日付があります。"
  end

  def self.attributes(row, mapping)
    { title: row["title"], description: row["notes"], starts_on: row["starts_on"], due_on: row["due_on"],
      status: row["status"], category: row["category"], origin: "import", source_key: row["source_key"],
      assignee: Task.normalize_assignee(mapping.fetch(row["assignee_raw"].to_s, "unknown")),
      source_details: row.slice("source_file", "source_sheet", "source_row", "assignee_raw", "category_raw") }
  end

  def self.commit(batch, mapping)
    batch.with_lock do
      return batch if batch.status == "committed"
      labels = batch.rows.map { |r| r["assignee_raw"].to_s }.uniq
      raise Invalid, "すべての担当の割り当てを選んでください。" unless labels.all? { |label| Task::ASSIGNEES.key?(Task.normalize_assignee(mapping[label])) }
      batch.wedding.with_lock do
        added = skipped = 0
        batch.rows.each do |row|
          if batch.wedding.tasks.exists?(source_key: row["source_key"])
            skipped += 1
          else
            batch.wedding.tasks.create!(attributes(row, mapping))
            added += 1
          end
        end
        batch.update!(status: "committed", imported_count: added, skipped_count: skipped, committed_at: Time.current)
      end
    end
    batch
  end
end
