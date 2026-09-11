require "digest"
require "set"
require "stringio"
require "zip"
require "nokogiri"

class SpreadsheetImport
  class Invalid < StandardError; end

  MAX_FILE_BYTES = 25.megabytes
  MAX_ARCHIVE_BYTES = 100.megabytes
  MAX_ROWS = 10_000
  MAX_FILES = 2
  MAPPING_VERSION = "xlsx-v1".freeze
  IGNORED_SHEETS = /\A(?:今週|ダッシュボード|使い方|サンプル)/.freeze
  BGM_DITTO_MARKERS = %w[〃 々 同上 " “ ”].freeze
  ROW_ORDER = %w[master cash_gift_rule household guest gift_set gift_assignment budget_item task bgm].freeze

  def self.prepare(wedding, files)
    new(wedding, files).prepare
  end

  def self.commit(batch, mapping, confirmed: false)
    new(batch.wedding, []).commit(batch, mapping, confirmed: confirmed)
  end

  # Repairs BGM rows imported before ditto markers were expanded. This is safe to
  # run more than once: after the marker items are merged, it has nothing left to do.
  def self.repair_bgm_ditto_items!(wedding)
    new(wedding, []).repair_bgm_ditto_items!
  end

  def initialize(wedding, files)
    @wedding = wedding
    @files = Array(files).compact_blank
  end

  def repair_bgm_ditto_items!
    ActiveRecord::Base.transaction do
      previous_item = nil
      repaired = 0
      @wedding.planning_items.where(category: "music").order(:id).to_a.each do |item|
        item.planning_options.to_a.each do |option|
          detail = option.music_detail
          next unless detail && detail.original_text.to_s.include?("シーン:〃") && !bgm_candidate_present?(detail)
          option.destroy!
          repaired += 1
        end
        item.association(:planning_options).reset
        marker_item = bgm_ditto_marker?(item.title)
        if marker_item && previous_item
          item.planning_options.to_a.each do |option|
            detail = option.music_detail
            if detail && !bgm_candidate_present?(detail)
              option.destroy!
              next
            end
            if option.selected? && previous_item.planning_options.where(status: "selected").exists?
              option.update!(status: "draft")
            end
            option.update!(planning_item: previous_item)
            if detail
              detail.update!(scene: previous_item.title)
              candidate_title = detail.selected_track.presence || detail.wish_track_a.presence || detail.wish_track_b.presence
              option.update!(title: bgm_option_title(candidate_title)) if option.title.to_s == item.title.to_s
            end
          end
          item.association(:planning_options).reset
          item.destroy!
          repaired += 1
        else
          previous_item = item unless marker_item
        end
      end
      repaired
    end
  end

  def prepare
    raise Invalid, "xlsxファイルを1〜2個選んでください。" unless @files.size.between?(1, MAX_FILES)

    workbooks = @files.map { |file| read_workbook(file) }
    raise Invalid, "対象のExcelテンプレートを認識できません。" if workbooks.none? { |book| book[:recognized] }
    total_rows = workbooks.sum { |book| book[:sheets].sum { |sheet| sheet[:rows].size } }
    raise Invalid, "Excelの合計行数は#{MAX_ROWS}行までです。" if total_rows > MAX_ROWS

    digest = Digest::SHA256.hexdigest(workbooks.map { |book| [book[:filename], book[:digest]].join(":") }.sort.join("\0"))
    existing = @wedding.spreadsheet_import_batches.find_by(digest: digest)
    return existing if existing

    normalized = normalize_workbooks(workbooks)
    raise Invalid, "取り込める行がありません。対象シートと入力内容を確認してください。" if normalized.empty?

    rows = normalized.sort_by { |row| [ROW_ORDER.index(row[:row_kind]) || ROW_ORDER.length, row[:sheet_name], row[:row_number]] }
    existing_targets = @wedding.spreadsheet_import_rows.where(source_key: rows.map { |row| row[:source_key] }).pluck(:source_key, :target_type, :target_id).to_h { |key, type, id| [key, [type, id]] }
    existing_source_keys = existing_targets.keys.to_set
    source_metadata = {
      "files" => workbooks.map { |book| { "filename" => book[:filename], "digest" => book[:digest], "bytes" => book[:bytes] } },
      "mapping_version" => MAPPING_VERSION,
      "assignee_labels" => rows.filter_map { |row| row[:assignee_raw].presence }.uniq
    }
    warnings = rows.flat_map { |row| Array(row[:warnings]) }.uniq
    SpreadsheetImportBatch.transaction do
      batch = @wedding.spreadsheet_import_batches.create!(
        digest: digest, mapping_version: MAPPING_VERSION, source_metadata: source_metadata,
        warnings: warnings, row_count: rows.size, warning_count: warnings.size
      )
      existing_tasks = @wedding.tasks.where(origin: "import").order(:id).limit(2000).to_a
      existing_task_keys = existing_tasks.filter_map(&:source_key).to_set
      existing_task_positions = existing_tasks.each_with_object({}) do |task, positions|
        details = task.source_details.to_h.stringify_keys
        sheet = details["source_sheet"].presence || details["sheet_name"].presence
        row_number = details["source_row"].presence || details["row_number"].presence
        positions[[sheet.to_s, row_number.to_i]] = task if sheet.present? && row_number.present?
      end
      rows.each do |row|
        position_task = row[:row_kind] == "task" && existing_task_positions[[row[:sheet_name].to_s, row[:row_number].to_i]]
        duplicate = existing_source_keys.include?(row[:source_key]) || (row[:row_kind] == "task" && (existing_task_keys.include?(row[:source_key]) || position_task))
        state = duplicate ? "conflict" : (row[:warnings].present? ? "ready" : "pending")
        target_type, target_id = existing_targets[row[:source_key]] || [nil, nil]
        if row[:row_kind] == "task" && target_id.nil? && position_task
          task = position_task
          target_type, target_id = ["Task", task.id]
        elsif row[:row_kind] == "task" && target_id.nil?
          task = @wedding.tasks.find_by(source_key: row[:source_key])
          target_type, target_id = ["Task", task.id] if task
        end
        batch.rows.create!(
          wedding: @wedding, row_kind: row[:row_kind], sheet_name: row[:sheet_name], row_number: row[:row_number],
          source_key: row[:source_key], state: state, target_type: target_type, target_id: target_id, mapping_label: row[:assignee_raw],
          original_data: row.except(:warnings), warnings: row[:warnings]
        )
      end
      batch
    end
  rescue Zip::Error, Nokogiri::XML::SyntaxError, IOError, SystemCallError, ArgumentError => error
    raise Invalid, "xlsxを読み込めません。壊れていないExcelファイルを選んでください。（#{error.message.truncate(120)}）"
  end

  def commit(batch, mapping, confirmed: false)
    @allow_cached_candidates = confirmed
    @planning_items_by_title = nil
    raise Invalid, "この取り込みは既に反映済みです。" if batch.state == "committed"
    rows = batch.rows.order(:id).to_a
    labels = rows.filter_map(&:mapping_label).uniq
    normalized_mapping = labels.to_h { |label| [label, Task.normalize_assignee(mapping[label.to_s] || mapping[label])] }
    unless labels.all? { |label| Task::ASSIGNEES.key?(normalized_mapping[label]) }
      raise Invalid, "担当A/Bの割り当てをすべて確認してください。"
    end
    if rows.any? { |row| row.state == "invalid" }
      raise Invalid, "入力エラーの行があります。修正してから反映してください。"
    end

    ActiveRecord::Base.transaction do
      batch.with_lock do
        @contexts = { households: {}, gift_sets: {}, cash_gift_rules: {} }
        imported = skipped = 0
        rows.each do |row|
          if row.state == "conflict" || row.state == "skipped"
            restore_context!(row)
            row.update!(state: "skipped")
            skipped += 1
            next
          end
          import_row!(row, normalized_mapping)
          if row.state == "skipped"
            row.update!(state: "skipped", target_type: row.target_type, target_id: row.target_id)
            skipped += 1
            next
          end
          row.update!(state: "imported", target_type: row.target_type, target_id: row.target_id)
          imported += 1
        end
        batch.update!(state: "committed", imported_count: imported, skipped_count: skipped, committed_at: Time.current)
      end
    end
    batch
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
    raise Invalid, "Excelの反映に失敗しました。追加内容は保存されていません。#{error.message.truncate(160)}"
  end

  private

  def read_workbook(file)
    bytes = if file.respond_to?(:read)
      file.rewind if file.respond_to?(:rewind)
      file.read(MAX_FILE_BYTES + 1).to_s
    else
      path = file.to_s
      raise Invalid, "xlsxファイルを選択してください。" if path.blank? || !File.file?(path)
      File.binread(path, MAX_FILE_BYTES + 1)
    end
    raise Invalid, "1ファイル#{MAX_FILE_BYTES / 1.megabyte}MB以下にしてください。" if bytes.bytesize > MAX_FILE_BYTES
    raise Invalid, "xlsx（Excel）ファイルを選んでください。" unless bytes.start_with?("PK\x03\x04")

    digest = Digest::SHA256.hexdigest(bytes)
    workbook = nil
    Zip::File.open_buffer(StringIO.new(bytes)) do |zip|
      entries = []
      zip.each { |entry| entries << entry }
      validate_zip!(entries)
      shared = read_shared_strings(zip)
      workbook_xml = read_entry(zip, "xl/workbook.xml")
      rels_xml = read_entry(zip, "xl/_rels/workbook.xml.rels")
      sheets = parse_sheets(zip, workbook_xml, rels_xml, shared)
      workbook = { filename: file.respond_to?(:original_filename) ? file.original_filename.to_s : "upload.xlsx", digest: digest,
        bytes: bytes.bytesize, sheets: sheets, recognized: recognized_sheets?(sheets) }
    end
    workbook
  end

  def validate_zip!(entries)
    total = 0
    entries.each do |entry|
      name = entry.name.to_s
      raise Invalid, "xlsxの展開先パスが不正です。" if name.start_with?("/") || name.split("/").include?("..")
      raise Invalid, "暗号化されたxlsxは利用できません。" if entry.respond_to?(:encrypted?) && entry.encrypted?
      next if entry.directory?
      total += entry.size.to_i
      raise Invalid, "xlsxの展開後サイズは#{MAX_ARCHIVE_BYTES / 1.megabyte}MBまでです。" if total > MAX_ARCHIVE_BYTES
      if entry.compressed_size.to_i.positive? && entry.size.to_i > 1.megabyte && entry.size.to_f / entry.compressed_size.to_f > 1000
        raise Invalid, "圧縮率が異常なxlsxは利用できません。"
      end
      raise Invalid, "マクロ・外部リンク付きxlsxは利用できません。" if name.match?(%r{\Axl/(?:vbaProject\.bin|externalLinks/)})
    end
    required = entries.map(&:name)
    raise Invalid, "xlsxの構造が不正です。" unless required.include?("xl/workbook.xml") && required.any? { |name| name.end_with?("workbook.xml.rels") }
  end

  def read_entry(zip, name)
    entry = zip.find_entry(name)
    raise Invalid, "xlsxの#{name}がありません。" unless entry
    Nokogiri::XML(entry.get_input_stream.read(MAX_ARCHIVE_BYTES + 1)) { |config| config.strict.nonet }
  end

  def read_shared_strings(zip)
    entry = zip.find_entry("xl/sharedStrings.xml")
    return [] unless entry
    xml = Nokogiri::XML(entry.get_input_stream.read(MAX_ARCHIVE_BYTES + 1)) { |config| config.strict.nonet }
    xml.xpath("//*[local-name()='si']").map { |si| si.xpath(".//*[local-name()='t']").map(&:text).join }
  end

  def parse_sheets(zip, workbook_xml, rels_xml, shared)
    date1904 = workbook_xml.at_xpath("//*[local-name()='workbookPr']")&.[]("date1904") == "1"
    relationships = rels_xml.xpath("//*[local-name()='Relationship']").to_h { |node| [node["Id"], node["Target"]] }
    workbook_xml.xpath("//*[local-name()='sheet']").filter_map do |sheet|
      target = relationships[sheet["{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"] || sheet["r:id"]]
      next unless target
      target = target.sub(%r{\A/}, "")
      target = "xl/#{target}" unless target.start_with?("xl/")
      entry = zip.find_entry(target)
      next unless entry
      xml = Nokogiri::XML(entry.get_input_stream.read(MAX_ARCHIVE_BYTES + 1)) { |config| config.strict.nonet }
      rows = xml.xpath("//*[local-name()='sheetData']/*[local-name()='row']").map do |row|
        cells = row.xpath("./*[local-name()='c']").to_h do |cell|
          ref = cell["r"].to_s.gsub(/\d/, "")
          [ref, cell_value(cell, shared)]
        end
        { number: row["r"].to_i, cells: cells }
      end
      { name: sheet["name"].to_s, rows: rows, date1904: date1904 }
    end
  end

  def cell_value(cell, shared)
    formula = cell.at_xpath("./*[local-name()='f']")
    value = cell.at_xpath("./*[local-name()='v']")&.text
    type = cell["t"].to_s
    if formula
      return { value: nil, cached_value: value, formula: true }
    end
    value = cell.at_xpath("./*[local-name()='is']")&.xpath(".//*[local-name()='t']")&.map(&:text)&.join if type == "inlineStr"
    value = shared[value.to_i] if type == "s" && value.to_s.match?(/\A\d+\z/)
    { value: value.to_s.strip.presence, cached_value: nil, formula: false }
  end

  def normalize_workbooks(workbooks)
    rows = []
    workbooks.each do |book|
      book[:sheets].each do |sheet|
        next if sheet[:name].match?(IGNORED_SHEETS)
        rows.concat(parse_sheet(sheet, book[:digest]))
      end
    end
    rows
  end

  def parse_sheet(sheet, file_digest)
    header_row, headers = detect_headers(sheet)
    normalized = normalize_headers(headers)
    if sheet[:name].include?("マスタ")
      return parse_master(sheet, file_digest)
    elsif normalized.values.include?("氏名")
      return parse_guests(sheet, header_row, headers, file_digest)
    elsif normalized.values.include?("世帯名")
      return parse_households(sheet, header_row, headers, file_digest)
    elsif normalized.values.include?("ギフトグループ") && normalized.values.any? { |value| value.include?("引出物") || value.include?("引き出物") }
      return parse_gift_sets(sheet, header_row, headers, file_digest)
    elsif normalized.values.include?("区分") && normalized.values.include?("項目")
      return parse_budgets(sheet, header_row, headers, file_digest)
    elsif normalized.values.any? { |value| value.include?("シーン") } && normalized.values.any? { |value| value.include?("希望") }
      return parse_bgm(sheet, header_row, headers, file_digest)
    elsif sheet[:name].include?("タスク")
      return parse_tasks(sheet, header_row, headers, file_digest)
    end
    []
  end

  def parse_master(sheet, file_digest)
    sheet[:rows].drop(1).filter_map do |item|
      label = value(item, "A")
      amount = number(item, "B")
      next if label.blank? || amount.nil?
      build_row("cash_gift_rule", sheet, item, file_digest, { label: label, default_amount_yen: amount }, [])
    end
  end

  def parse_households(sheet, header_row, headers, file_digest)
    each_data_row(sheet, header_row).flat_map do |item|
      code = row_value(item, headers, "世帯ID")
      name = row_value(item, headers, "世帯名")
      next [] if name.blank?
      warnings = []
      warnings << "想定祝儀は数式または未入力のため要確認です。" if row_formula?(item, headers, "想定祝儀")
      warnings << "実績ご祝儀は受取日を確認するまで確定しません。" if row_value(item, headers, "実績祝儀").present? || row_formula?(item, headers, "実績祝儀")
      data = { code: code, name: name, cash_gift_label: row_value(item, headers, "祝儀区分"),
        gift_group: row_value(item, headers, "ギフトグループ"), travel_yen: number_for(item, headers, "お車代"), notes: row_value(item, headers, "備考") }
      rows = [build_row("household", sheet, item, file_digest, data, warnings)]
      if data[:gift_group].present?
        rows << build_row("gift_assignment", sheet, item, file_digest, { household_code: data[:code], gift_group: data[:gift_group] }, warnings)
      end
      rows
    end
  end

  def parse_guests(sheet, header_row, headers, file_digest)
    each_data_row(sheet, header_row).filter_map do |item|
      name = row_value(item, headers, "氏名")
      next if name.blank?
      data = { name: name, side: row_value(item, headers, "新郎新婦側"), relationship: row_value(item, headers, "属性"),
        gender: row_value(item, headers, "性別"), age_group: row_value(item, headers, "大人子供"),
        attendance: row_value(item, headers, "出欠"), household_code: row_value(item, headers, "世帯グループ"),
        seating_table: row_value(item, headers, "テーブル"), travel_yen: number_for(item, headers, "お車代"), roles: row_value(item, headers, "役割"),
        notes: row_value(item, headers, "備考") }
      warnings = []
      warnings << "お車代は概算として要確認です。" if data[:travel_yen].present? || row_formula?(item, headers, "お車代")
      build_row("guest", sheet, item, file_digest, data, warnings)
    end
  end

  def parse_gift_sets(sheet, header_row, headers, file_digest)
    each_data_row(sheet, header_row).filter_map do |item|
      group = row_value(item, headers, "ギフトグループ")
      next if group.blank?
      gifts = [[%w[引出物 引き出物], "gift"], [%w[引菓子 引き菓子], "sweet"], [%w[縁起物], "celebration"]].filter_map do |labels, kind|
        name = row_value_any(item, headers, *labels)
        next if name.blank?
        price_keys = labels.map { |label| "#{label}単価" }
        { name: name, kind: kind, unit_price_yen: number_for_any(item, headers, *price_keys),
          cached_unit_price_yen: cached_number_for_any(item, headers, *price_keys),
          formula_unit_price: formula_for_any?(item, headers, *price_keys), tax_basis: "exclusive", tax_rate: nil }
      end
      warnings = gifts.any? { |gift| gift[:formula_unit_price] } ? ["ギフト単価に数式キャッシュの概算候補があります。確認後にのみ採用します。"] : []
      warnings << "ギフト単価が未確認のため、金額を作成しません。" if gifts.any? { |gift| gift[:unit_price_yen].nil? && gift[:cached_unit_price_yen].nil? }
      build_row("gift_set", sheet, item, file_digest, { name: group, items: gifts }, warnings)
    end
  end

  def parse_budgets(sheet, header_row, headers, file_digest)
    each_data_row(sheet, header_row).filter_map do |item|
      title = row_value(item, headers, "項目")
      next if title.blank?
      warnings = []
      warnings << "見込額に数式キャッシュの概算候補があります。確認後にのみ採用します。" if row_formula?(item, headers, "見込額")
      warnings << "実績額は支払済みと断定せず要確認です。" if row_value(item, headers, "実績額").present? || row_formula?(item, headers, "実績額")
      build_row("budget_item", sheet, item, file_digest, { direction: row_value(item, headers, "区分"),
        category: row_value(item, headers, "カテゴリ"), title: title, quantity_basis_raw: row_value(item, headers, "数量区分"),
        unit_price: number_for(item, headers, "単価"), quantity: number_for(item, headers, "数量"),
        estimate: number_for(item, headers, "見込額"), cached_estimate: cached_number_for(item, headers, "見込額"),
        formula_estimate: formula_for?(item, headers, "見込額"), note: row_value(item, headers, "備考") }, warnings)
    end
  end

  def parse_tasks(sheet, header_row, headers, file_digest)
    if headers.blank?
      header_row = 3
      headers = { "A" => "title", "B" => "notes", "C" => "category", "D" => "starts_on", "E" => "due_on", "F" => "assignee", "G" => "status" }
    end
    each_data_row(sheet, header_row).filter_map do |item|
      title = row_value(item, headers, "title") || row_value(item, headers, "タスク") || value(item, "A")
      next if title.blank? || title.match?(/\A[-=_＿\s]+\z/) || title.include?("区切り")
      data = { title: title, notes: row_value(item, headers, "notes") || row_value(item, headers, "メモ"),
        category_raw: row_value(item, headers, "category") || row_value(item, headers, "カテゴリ"),
        starts_on: parse_date(item, headers, headers_for_key(headers, "starts_on", "開始日"), sheet[:date1904]), due_on: parse_date(item, headers, headers_for_key(headers, "due_on", "期限"), sheet[:date1904]),
        assignee_raw: row_value(item, headers, "assignee") || row_value(item, headers, "担当"),
        status_raw: row_value(item, headers, "status") || row_value(item, headers, "ステータス") || row_value(item, headers, "状態") }
      next if [data[:notes], data[:category_raw], data[:starts_on], data[:due_on], data[:assignee_raw], data[:status_raw]].all?(&:blank?)
      warnings = []
      warnings << "担当を確認してください。" if data[:assignee_raw].present? && Task.normalize_assignee(data[:assignee_raw]).in?(%w[person_a person_b both unknown]) == false
      warnings << "状態を確認してください。" if data[:status_raw].present? && enum_key(Task::STATUSES, data[:status_raw], nil).nil?
      warnings << "カテゴリを確認してください。" if data[:category_raw].present? && task_category_key(data[:category_raw]).nil?
      build_row("task", sheet, item, file_digest, data, warnings)
    end
  end

  def parse_bgm(sheet, header_row, headers, file_digest)
    previous_scene = nil
    each_data_row(sheet, header_row).filter_map do |item|
      raw_scene = row_value(item, headers, "シーン")
      scene = bgm_scene(raw_scene, previous_scene)
      previous_scene = scene if scene.present?
      values = headers.filter_map { |column, header| [header, row_value(item, headers, header)] if row_value(item, headers, header).present? }
      wishes = headers.select { |_column, header| header.include?("希望") }.map { |column, _| value(item, column) }.compact
      selected = headers.filter_map { |column, header| value(item, column) if header.include?("決定") || header.include?("曲名") }.compact.first
      artist = nil
      if selected.to_s.include?("/")
        selected, artist = selected.split("/", 2).map(&:strip)
      end
      offset = parse_offset(values.map(&:last).join(" "))
      candidate_values = [selected, artist, *wishes, offset].compact_blank
      next if raw_scene.blank? && candidate_values.empty?
      next if bgm_ditto_marker?(raw_scene) && candidate_values.empty?
      option_title = bgm_option_title(selected.presence || wishes.compact_blank.first)
      data = { title: scene.presence || selected.presence || "BGM", scene: scene, wish_track_a: wishes[0], wish_track_b: wishes[1],
        selected_track: selected, artist: artist, option_title: option_title, start_offset_seconds: offset,
        original_text: values.map { |pair| pair.join(":") }.join(" / ") }
      build_row("bgm", sheet, item, file_digest, data, [])
    end
  end

  def detect_headers(sheet)
    sheet[:rows].first(30).each do |row|
      headers = row[:cells].filter_map { |column, cell| [column, cell[:value]] if cell[:value].present? }
      normalized = normalize_headers(headers)
      return [row[:number], headers] if normalized.values.any? { |value| %w[氏名 世帯名 ギフトグループ 区分 項目].include?(value) } ||
        (normalized.values.any? { |value| value.include?("シーン") } && normalized.values.any? { |value| value.include?("希望") }) ||
        normalized.values.any? { |value| value.match?(/title|タスク|担当/i) }
    end
    [0, {}]
  end

  def normalize_headers(headers)
    headers.to_h { |column, value| [column, normalize(value)] }
  end

  def normalize(value)
    value.to_s.unicode_normalize(:nfkc).gsub(/[\s　]/, "").strip
  rescue ArgumentError
    value.to_s.strip
  end

  def each_data_row(sheet, header_row)
    sheet[:rows].select { |row| row[:number] > header_row && row[:cells].values.any? { |cell| cell[:value].present? || cell[:formula] } }
  end

  def row_value(row, headers, key)
    column = headers.find { |_column, value| normalize(value).include?(normalize(key)) }&.first
    value(row, column) if column
  end

  def row_value_any(row, headers, *keys)
    keys.filter_map { |key| row_value(row, headers, key) }.first
  end

  def row_formula?(row, headers, key)
    column = headers.find { |_column, value| normalize(value).include?(normalize(key)) }&.first
    column.present? && row[:cells][column]&.dig(:formula)
  end

  def headers_for_key(headers, *keys)
    keys.find { |key| headers.any? { |_column, value| normalize(value).include?(normalize(key)) } } || keys.first
  end

  def value(row, column)
    row[:cells][column.to_s][:value] if column && row[:cells][column.to_s]
  end

  def number(row, column)
    raw = value(row, column)
    raw.present? && Float(raw).to_i.to_s == raw.to_f.to_i.to_s ? raw.to_f.to_i : nil
  rescue ArgumentError, TypeError
    nil
  end

  def number_for(row, headers, key)
    column = headers.find { |_column, value| normalize(value).include?(normalize(key)) }&.first
    number(row, column)
  end

  def number_for_any(row, headers, *keys)
    keys.filter_map { |key| number_for(row, headers, key) }.first
  end

  def cached_number_for(row, headers, key)
    column = headers.find { |_column, value| normalize(value).include?(normalize(key)) }&.first
    raw = column && row[:cells][column]&.dig(:cached_value)
    raw.present? ? Float(raw).to_i : nil
  rescue ArgumentError, TypeError
    nil
  end

  def cached_number_for_any(row, headers, *keys)
    keys.filter_map { |key| cached_number_for(row, headers, key) }.first
  end

  def formula_for?(row, headers, key)
    column = headers.find { |_column, value| normalize(value).include?(normalize(key)) }&.first
    column.present? && row[:cells][column]&.dig(:formula)
  end

  def formula_for_any?(row, headers, *keys)
    keys.any? { |key| formula_for?(row, headers, key) }
  end

  def parse_date(row, headers, key, date1904 = false)
    raw = row_value(row, headers, key)
    return nil if raw.blank? || row_formula?(row, headers, key)
    if raw.to_s.match?(/\A\d+(?:\.\d+)?\z/)
      serial = raw.to_f
      origin = date1904 ? Date.new(1904, 1, 1) : Date.new(1899, 12, 30)
      return (origin + serial.floor).iso8601
    end
    Date.parse(raw).iso8601
  rescue Date::Error
    nil
  end

  def parse_offset(text)
    japanese = text.to_s.match(/(\d{1,2})\s*分\s*(\d{1,2})\s*秒/)
    return japanese[1].to_i * 60 + japanese[2].to_i if japanese

    colon = text.to_s.match(/(?:^|[^\d])(\d{1,2}):(\d{2})(?:[^\d]|$)/)
    colon ? colon[1].to_i * 60 + colon[2].to_i : nil
  end

  def bgm_ditto_marker?(scene)
    BGM_DITTO_MARKERS.include?(scene.to_s.strip)
  end

  def bgm_scene(raw_scene, previous_scene)
    return previous_scene if bgm_ditto_marker?(raw_scene) && previous_scene.present?
    raw_scene.presence
  end

  def bgm_option_title(value)
    value.to_s.gsub(/\s+/, " ").strip.presence || "未定"
  end

  def bgm_candidate_present?(detail)
    [detail.wish_track_a, detail.wish_track_b, detail.selected_track, detail.artist, detail.start_offset_seconds].compact_blank.any?
  end

  def build_row(kind, sheet, row, file_digest, data, warnings)
    source_key = if kind == "task"
      Digest::SHA256.hexdigest([file_digest, sheet[:name], row[:number]].to_json)
    else
      Digest::SHA256.hexdigest([kind, sheet[:name], row[:number]].join("\0"))
    end
    data.merge(source_file: "xlsx", source_sha256: file_digest, source_sheet: sheet[:name], source_row: row[:number],
      row_kind: kind, sheet_name: sheet[:name], row_number: row[:number], source_key: source_key,
      warnings: warnings, assignee_raw: data[:assignee_raw])
  end

  def recognized_sheets?(sheets)
    sheets.any? { |sheet| !sheet[:name].match?(IGNORED_SHEETS) && !parse_sheet(sheet, 0).empty? }
  end

  def import_row!(row, mapping)
    data = row.original_data.stringify_keys
    case row.row_kind
    when "cash_gift_rule"
      rule = @wedding.cash_gift_rules.find_or_create_by!(label: data["label"]) { |item| item.default_amount_yen = data["default_amount_yen"] || 0 }
      row.target_type, row.target_id = "CashGiftRule", rule.id
    when "household"
      rule = data["cash_gift_label"].present? ? @wedding.cash_gift_rules.find_by(label: data["cash_gift_label"]) : nil
      household = @wedding.households.find_or_initialize_by(code: data["code"].presence || "xlsx-#{row.source_key[0, 10]}")
      household.assign_attributes(name: data["name"], notes: data["notes"], cash_gift_rule: rule)
      household.save!
      household.ensure_cash_gift_budget_item! if rule
      ensure_household_travel_budget!(household, data["travel_yen"]) if data["travel_yen"].present?
      @contexts[:households][data["code"].to_s] = household
      row.target_type, row.target_id = "Household", household.id
    when "guest"
      household = @contexts[:households][data["household_code"].to_s]
      raise Invalid, "世帯参照を解決できません。行を確認してください。" if data["household_code"].present? && household.nil?
      seating_table = find_seating_table(data["seating_table"])
      guest = @wedding.guests.create!(name: data["name"], household: household, seating_table: seating_table,
        side: enum_key(Guest::SIDES, data["side"], "unknown"), relationship: data["relationship"],
        gender: enum_key(Guest::GENDERS, data["gender"], nil), age_group: enum_key(Guest::AGE_GROUPS, data["age_group"], "adult"),
        attendance: enum_key(Guest::ATTENDANCES, data["attendance"], "unanswered"), notes: data["notes"], roles: role_keys(data["roles"] || data["role"]))
      ensure_guest_travel_budget!(guest, data["travel_yen"]) if data["travel_yen"].present?
      row.target_type, row.target_id = "Guest", guest.id
    when "gift_set"
      set = @wedding.gift_sets.find_or_initialize_by(name: data["name"])
      set.save!
      Array(data["items"]).each do |item|
        unit_price = item["unit_price_yen"] || ( @allow_cached_candidates ? item["cached_unit_price_yen"] : nil )
        next if unit_price.nil?
        set.gift_set_items.find_or_create_by!(name: item["name"]) do |record|
          record.kind = item["kind"]
          record.unit_price_yen = unit_price
          record.tax_basis = "unknown"
        end
      end
      @contexts[:gift_sets][data["name"].to_s] = set
      row.target_type, row.target_id = "GiftSet", set.id
    when "gift_assignment"
      household = @contexts[:households][data["household_code"].to_s]
      gift_set = @contexts[:gift_sets][data["gift_group"].to_s]
      raise Invalid, "引き出物の世帯参照を解決できません。行を確認してください。" unless household && gift_set
      if gift_set.gift_set_items.empty?
        row.state = "skipped"
        row.error = "引き出物単価が未確認のため、割当と予算明細を作成しません。"
        row.target_type, row.target_id = "GiftSet", gift_set.id
        return
      end
      assignment = @wedding.gift_assignments.find_or_initialize_by(household: household)
      assignment.assign_attributes(gift_set: gift_set, quantity: 1, included: true)
      assignment.save!
      GiftAssignmentBudgetItemSync.call!(assignment)
      row.target_type, row.target_id = "GiftAssignment", assignment.id
    when "budget_item"
      unit_price = data["unit_price"]
      quantity = data["quantity"]
      warnings = Array(row.warnings)
      formula_estimate = data["formula_estimate"]
      amount = if formula_estimate
        @allow_cached_candidates ? data["cached_estimate"] : nil
      else
        data["estimate"]
      end
      if data["estimate"].blank? && (unit_price.blank? || quantity.blank?)
        warnings << "単価または数量が不明のため金額未確認です。"
      end
      warnings << "単価・数量は税区分不明のため金額未確認です。" if data["estimate"].blank? && unit_price.present? && quantity.present?
      row.warnings = warnings.uniq
      item = @wedding.budget_items.create!(direction: data["direction"] == "収入" ? "income" : "expense", category: data["category"].presence || "other",
        title: data["title"], amount_yen: amount, unit_price: unit_price, manual_quantity: quantity,
        certainty: "estimate", inclusion: "included", calculation_mode: "manual", quantity_basis: "manual",
        tax_basis: "unknown", source_kind: "manual")
      row.target_type, row.target_id = "BudgetItem", item.id
    when "task"
      existing = @wedding.tasks.find_by(source_key: row.source_key)
      if existing
        row.state = "skipped"
        row.target_type, row.target_id = "Task", existing.id
      else
        task = @wedding.tasks.create!(title: data["title"], description: data["notes"], category: task_category_key(data["category_raw"]) || "other",
          assignee: mapping[data["assignee_raw"].to_s] || Task.normalize_assignee(data["assignee_raw"]).presence || "unknown",
          starts_on: data["starts_on"], due_on: data["due_on"], status: enum_key(Task::STATUSES, data["status_raw"], "todo"),
          origin: "import", source_key: row.source_key,
          source_details: data.slice("source_file", "source_sheet", "source_row", "source_sha256", "sheet_name", "row_number", "assignee_raw", "category_raw"))
        row.target_type, row.target_id = "Task", task.id
      end
    when "bgm"
      item = planning_item_for_bgm(data["title"])
      option = item.planning_options.create!(wedding: @wedding, title: data["option_title"].presence || data["selected_track"].presence || "未定",
        status: data["selected_track"].present? ? "selected" : "draft")
      option.create_music_detail!(wedding: @wedding, planning_option: option, wish_track_a: data["wish_track_a"],
        wish_track_b: data["wish_track_b"], selected_track: data["selected_track"], artist: data["artist"],
        start_offset_seconds: data["start_offset_seconds"], original_text: data["original_text"], scene: data["scene"])
      row.target_type, row.target_id = "PlanningItem", item.id
    else
      raise Invalid, "未対応の行種別です。"
    end
  end

  def planning_item_for_bgm(title)
    @planning_items_by_title ||= @wedding.planning_items.where(category: "music").to_a.index_by(&:title)
    @planning_items_by_title[title] ||= @wedding.planning_items.create!(title: title, category: "music")
  end

  def enum_key(mapping, raw, fallback)
    return fallback if raw.blank?
    return raw if mapping.key?(raw.to_s)
    mapping.key(raw.to_s) || fallback
  end

  def task_category_key(raw)
    return nil if raw.blank?
    return raw if Task::CATEGORIES.key?(raw.to_s)
    return Task::CATEGORIES.key(raw.to_s) if Task::CATEGORIES.value?(raw.to_s)
    ImportTasks::CATEGORY_MAP[raw.to_s]
  end

  def restore_context!(row)
    return unless row.target_id
    data = row.original_data.stringify_keys
    case row.row_kind
    when "household"
      household = @wedding.households.find_by(id: row.target_id)
      @contexts[:households][data["code"].to_s] = household if household
    when "gift_set"
      gift_set = @wedding.gift_sets.find_by(id: row.target_id)
      @contexts[:gift_sets][data["name"].to_s] = gift_set if gift_set
    end
  end

  def role_keys(raw)
    Array(raw.to_s.split(/[、,，\/\s]+/)).filter_map do |label|
      next if label.blank?
      enum_key(Guest::ROLES, label, nil)
    end.uniq
  end

  def find_seating_table(label)
    return nil if label.blank?
    @wedding.seating_tables.find_or_create_by!(label: label.to_s.strip)
  end

  def ensure_guest_travel_budget!(guest, amount)
    @wedding.budget_items.find_or_create_by!(source_kind: "travel_guest", source_id: guest.id) do |item|
      item.assign_attributes(direction: "expense", category: "travel", title: "#{guest.name}のお車代", amount_yen: amount.to_i,
        certainty: "estimate", inclusion: "included", calculation_mode: "manual", tax_basis: "unknown")
    end
  end

  def ensure_household_travel_budget!(household, amount)
    @wedding.budget_items.find_or_create_by!(source_kind: "travel_household", source_id: household.id) do |item|
      item.assign_attributes(direction: "expense", category: "travel", title: "#{household.name}のお車代", amount_yen: amount.to_i,
        certainty: "estimate", inclusion: "included", calculation_mode: "manual", tax_basis: "unknown")
    end
  end
end
