require "test_helper"
require "cgi"
require "zip"

class SpreadsheetImportTest < ActiveSupport::TestCase
  test "previews the supported sheets in deterministic order and is idempotent" do
    wedding = create_wedding
    with_uploads(sample_workbook) do |uploads|
      batch = SpreadsheetImport.prepare(wedding, uploads)
      assert_equal %w[cash_gift_rule household guest gift_set gift_assignment budget_item task bgm],
        batch.rows.order(:id).map(&:row_kind).uniq
      assert_equal 1, batch.rows.where(row_kind: "cash_gift_rule").count
      assert_equal 1, batch.rows.where(row_kind: "task").count
      task_row = batch.rows.find_by!(row_kind: "task")
      file_digest = batch.source_metadata.fetch("files").first.fetch("digest")
      assert_equal Digest::SHA256.hexdigest([file_digest, task_row.sheet_name, task_row.row_number].to_json), task_row.source_key
      assert batch.rows.any? { |row| row.warnings.present? }
      assert_equal batch.id, SpreadsheetImport.prepare(wedding, uploads).id
      assert_equal 1, wedding.spreadsheet_import_batches.count
    end
  end

  test "commits master, household, guest, gift, budget, task and BGM rows atomically" do
    wedding = create_wedding
    with_uploads(sample_workbook) do |uploads|
      batch = SpreadsheetImport.prepare(wedding, uploads)
      SpreadsheetImport.commit(batch, { "旧担当" => "person_a" }, confirmed: true)
      assert_equal "committed", batch.reload.state
      assert_equal 1, wedding.cash_gift_rules.count
      assert_equal 1, wedding.households.count
      assert_equal 1, wedding.guests.count
      assert_equal 1, wedding.gift_sets.count
      assert_equal 1, wedding.gift_assignments.count
      assert_equal 1000, wedding.gift_assignments.first.budget_item.amount_yen
      assert_equal 1, wedding.budget_items.where(source_kind: "manual").count
      assert_equal 1, wedding.tasks.where(origin: "import").count
      assert_equal 1, wedding.planning_items.where(category: "music").count
      assert_equal "架空決定曲", wedding.planning_items.where(category: "music").first.planning_options.first.music_detail.selected_track
      assert_equal "selected", wedding.planning_items.where(category: "music").first.planning_options.first.status
    end
  end

  test "does not execute formulas and never creates MoneyMovement from actual amounts" do
    wedding = create_wedding
    with_uploads(sample_workbook) do |uploads|
      batch = SpreadsheetImport.prepare(wedding, uploads)
      budget = batch.rows.find { |row| row.row_kind == "budget_item" }
      assert_nil budget.original_data["estimate"]
      assert_equal 1000, budget.original_data["cached_estimate"]
      assert_includes budget.warnings, "見込額に数式キャッシュの概算候補があります。確認後にのみ採用します。"
      gift = batch.rows.find { |row| row.row_kind == "gift_set" }
      assert_equal 1000, gift.original_data["items"].first["cached_unit_price_yen"]
      assert_includes gift.warnings, "ギフト単価に数式キャッシュの概算候補があります。確認後にのみ採用します。"
      SpreadsheetImport.commit(batch, { "旧担当" => "person_a" })
      assert_empty wedding.money_movements
      assert_empty wedding.gift_assignments
      assert_equal "estimate", wedding.budget_items.where(source_kind: "manual").sole.certainty
    end
  end

  test "adopts cached gift prices only after confirmation and rolls back as one transaction" do
    wedding = create_wedding
    with_uploads(sample_workbook) do |uploads|
      batch = SpreadsheetImport.prepare(wedding, uploads)
      ActiveRecord::Base.transaction do
        SpreadsheetImport.commit(batch, { "旧担当" => "person_a" }, confirmed: true)
        assert_equal 1, wedding.gift_assignments.count
        assert_equal 1000, wedding.gift_assignments.first.budget_item.amount_yen
        raise ActiveRecord::Rollback
      end
      assert_empty wedding.gift_assignments.reload
      assert_equal "pending", batch.reload.state
    end
  end

  test "rejects corrupt and unsafe archives with explanatory errors" do
    wedding = create_wedding
    assert_raises(SpreadsheetImport::Invalid) { SpreadsheetImport.prepare(wedding, [StringIO.new("not an xlsx")]) }
    with_uploads(zip_with_entry("../escape.txt", "架空")) do |uploads|
      error = assert_raises(SpreadsheetImport::Invalid) { SpreadsheetImport.prepare(wedding, uploads) }
      assert_includes error.message, "パス"
    end
  end

  test "commit rollback leaves all business records untouched when a reference is unresolved" do
    wedding = create_wedding
    with_uploads(sample_workbook(gift_group: "存在しない架空ギフト", gift_definition_group: "架空ギフト")) do |uploads|
      batch = SpreadsheetImport.prepare(wedding, uploads)
      assert_raises(SpreadsheetImport::Invalid) { SpreadsheetImport.commit(batch, { "旧担当" => "person_a" }) }
      wedding.reload
      assert_empty wedding.households.reload
      assert_empty wedding.gift_sets.reload
      assert_empty wedding.guests.reload
      assert_equal "pending", batch.reload.state
    end
  end

  test "detects an imported JSON task at the same sheet row when the xlsx digest changes" do
    wedding = create_wedding
    first = sample_workbook
    with_uploads(first) do |uploads|
      first_batch = SpreadsheetImport.prepare(wedding, uploads)
      task_row = first_batch.rows.find_by!(row_kind: "task")
      wedding.tasks.create!(title: "既存架空タスク", category: "other", status: "todo", assignee: "unknown", origin: "import",
        source_key: "旧JSONの架空キー", source_details: { "source_sheet" => task_row.sheet_name, "source_row" => task_row.row_number })
    end
    with_uploads(sample_workbook(task_title: "変更後の架空タスク")) do |uploads|
      changed = SpreadsheetImport.prepare(wedding, uploads)
      task_row = changed.rows.find_by!(row_kind: "task")
      assert_equal "conflict", task_row.state
      assert_equal "Task", task_row.target_type
      assert_equal wedding.tasks.where(origin: "import").sole.id, task_row.target_id
    end
  end

  private

  def with_uploads(bytes)
    Tempfile.create(["架空移行", ".xlsx"]) do |file|
      file.binmode
      file.write(bytes)
      file.rewind
      yield [Rack::Test::UploadedFile.new(file.path, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")]
    end
  end

  def sample_workbook(gift_group: "架空ギフト", gift_definition_group: gift_group, task_title: "架空タスク")
    sheets = {
      "マスタ祝儀・設定" => [["祝儀区分", "基本想定額（円）"], ["架空区分", "50000"], ["説明だけの行", ""]],
      "世帯グループ" => [["世帯ID", "世帯名", "祝儀区分", "想定祝儀（円）", "ギフトグループ", "備考"],
        ["G001", "架空世帯", "架空区分", [:formula, "SUM(A1)", "50000"], gift_group, ""]],
      "ゲスト一覧" => [["氏名", "新郎新婦側", "属性", "性別", "大人子供", "出欠", "世帯グループ", "備考"],
        ["架空ゲスト", "新郎側", "友人", "その他", "大人", "出席", "G001", ""]],
      "ギフト設定" => [["ギフトグループ", "引き出物", "引き出物単価（円）税抜き"],
        [gift_definition_group, "架空品", [:formula, "SUM(C2)", "1000"]]],
      "収支明細" => [["区分", "カテゴリ", "項目", "数量区分", "単価（円）", "数量", "見込額（円）", "実績額（円）"],
        ["支出", "架空", "架空費用", "手動", "1000", "1", [:formula, "SUM(E2:F2)", "1000"], "900"]],
      "タスク一覧" => [["title", "notes", "category", "assignee", "status"], [task_title, "架空メモ", "other", "旧担当", "todo"], ["区切り見出し", "", "", "", ""]],
      "BGMリスト" => [["No", "シーン", "二人希望", "架空決定曲", "何分何秒から流すか"], ["1", "入場", "架空希望", "架空決定曲", "1分30秒"]]
    }
    xlsx_bytes(sheets)
  end

  def zip_with_entry(name, content)
    Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry(name)
      zip.write(content)
    end.string
  end

  def xlsx_bytes(sheets)
    workbook_sheets = sheets.keys.each_with_index.map { |name, index| %(<sheet name="#{CGI.escapeHTML(name)}" sheetId="#{index + 1}" r:id="rId#{index + 1}"/>) }.join
    workbook = %(<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>#{workbook_sheets}</sheets></workbook>)
    rels = sheets.keys.each_with_index.map { |_name, index| %(<Relationship Id="rId#{index + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet#{index + 1}.xml"/>) }.join
    content_types = sheets.keys.each_with_index.map { |_name, index| %(<Override PartName="/xl/worksheets/sheet#{index + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>) }.join
    entries = {
      "[Content_Types].xml" => %(<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/>#{content_types}<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/></Types>),
      "xl/workbook.xml" => workbook,
      "xl/_rels/workbook.xml.rels" => %(<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">#{rels}</Relationships>)
    }
    sheets.each_with_index { |(_name, rows), index| entries["xl/worksheets/sheet#{index + 1}.xml"] = sheet_xml(rows) }
    Zip::OutputStream.write_buffer { |zip| entries.each { |name, content| zip.put_next_entry(name); zip.write(content) } }.string
  end

  def sheet_xml(rows)
    body = rows.each_with_index.map do |row, row_index|
      cells = row.each_with_index.filter_map do |value, column_index|
        next if value.nil?
        ref = (column_index + 65).chr
        if value.is_a?(Array) && value.first == :formula
          %(<c r="#{ref}#{row_index + 1}"><f>#{CGI.escapeHTML(value[1])}</f><v>#{CGI.escapeHTML(value[2])}</v></c>)
        else
          %(<c r="#{ref}#{row_index + 1}" t="inlineStr"><is><t>#{CGI.escapeHTML(value.to_s)}</t></is></c>)
        end
      end.join
      %(<row r="#{row_index + 1}">#{cells}</row>)
    end.join
    %(<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>#{body}</sheetData></worksheet>)
  end
end
