require "test_helper"
require "erb"
require "yaml"

class Phase3Test < ActionDispatch::IntegrationTest
  PNG_1X1 = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=").freeze

  setup do
    @owner = create_owner
    @wedding = create_wedding(@owner)
    sign_in(@owner)
  end

  test "document accepts attachment-only input and serves it only through wedding scope" do
    Tempfile.create(["架空添付", ".png"]) do |file|
      file.binmode
      file.write(PNG_1X1)
      file.rewind
      upload = Rack::Test::UploadedFile.new(file.path, "image/png")
      post documents_path, params: { document: { title: "架空画像資料", attachments: [upload] }, save_only: "1" }
    end

    document = @wedding.documents.order(:id).last
    assert_redirected_to document_path(document)
    assert_equal "photo", document.source_type
    assert_equal "unknown", document.direction
    assert_nil document.reload.original_text
    attachment = document.attachments.attachments.sole
    get document_attachment_path(document, attachment)
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal PNG_1X1, response.body
    assert_empty document.analysis_runs
    assert_empty document.change_sets
    content_hash = document.content_hash
    blob = document.attachments.attachments.sole.blob
    blob.singleton_class.send(:define_method, :download) { flunk("memo更新で添付をdownloadしない") }
    document.update!(memo: "後から付けた架空メモ")
    assert_equal content_hash, document.reload.content_hash

    other = create_wedding
    sign_in(other.users.first)
    get document_attachment_path(document, attachment)
    assert_response :not_found
  end

  test "document form keeps only the raw input and auto classifies text" do
    get new_document_path
    assert_response :success
    assert_select "select[name='document[source_type]']", count: 0
    assert_select "select[name='document[direction]']", count: 0
    assert_select "input[name='document[occurred_at]']", count: 0
    assert_includes response.body, "入力形式と情報元を分けて整理します"

    post documents_path, params: { document: { original_text: "文章入力だけで保存する" }, save_only: "1" }
    document = @wedding.documents.order(:id).last
    assert_equal "text", document.source_type
    assert_equal "unknown", document.direction
    assert_nil document.occurred_at
  end

  test "document filters keep input format and origin as separate axes" do
    @wedding.documents.create!(title: "メール連絡", source_type: "email", direction: "incoming", original_text: "メール本文")
    @wedding.documents.create!(title: "LINE連絡", source_type: "line", direction: "incoming", original_text: "LINE本文")
    @wedding.documents.create!(title: "打ち合わせメモ", source_type: "meeting", direction: "incoming", original_text: "打ち合わせ本文")
    @wedding.documents.create!(title: "写真資料", source_type: "photo", direction: "unknown", original_text: "写真の説明")

    get documents_path(media: "text")
    assert_response :success
    assert_includes response.body, "メール連絡"
    assert_includes response.body, "LINE連絡"
    assert_includes response.body, "打ち合わせメモ"
    refute_includes response.body, "写真資料"
    assert_includes response.body, "写真・スキャン"
    assert_includes response.body, "PDF・ファイル"
    assert_includes response.body, "打ち合わせ"
    assert_select "nav.tabs a", text: "打ち合わせ", count: 0
    assert_select "select[name='origin'] option", text: "打ち合わせ", count: 1

    get documents_path(origin: "meeting")
    assert_response :success
    assert_includes response.body, "打ち合わせメモ"
    refute_includes response.body, "メール連絡"

    get documents_path(source: "meeting")
    assert_response :success
    assert_includes response.body, "打ち合わせメモ"
    refute_includes response.body, "メール連絡"
  end

  test "save only does not start analysis or cross-document organization" do
    post documents_path, params: { document: { title: "保存だけの架空資料", source_type: "meeting", direction: "incoming", original_text: "保存だけ確認する" }, save_only: "1" }
    document = @wedding.documents.order(:id).last
    assert_redirected_to document_path(document)
    assert_equal "資料を保存しました。", flash[:notice]
    assert_empty document.reload.analysis_runs
    assert_empty document.change_sets
  end

  test "document rejects empty, svg, and oversized attachment input" do
    post documents_path, params: { document: { title: "空資料", source_type: "other", direction: "unknown" }, save_only: "1" }
    assert_response :unprocessable_entity

    with_document_limit(:MAX_TOTAL_ATTACHMENT_BYTES, 1) do
      Tempfile.create(["架空合計", ".png"]) do |file|
        file.binmode
        file.write(PNG_1X1)
        file.rewind
        post documents_path, params: { document: { title: "合計超過", source_type: "other", direction: "unknown", attachments: [Rack::Test::UploadedFile.new(file.path, "image/png")] }, save_only: "1" }
      end
      assert_response :unprocessable_entity
    end
    assert_empty @wedding.documents

    Tempfile.create(["架空", ".svg"]) do |file|
      file.write("<svg xmlns='http://www.w3.org/2000/svg'></svg>")
      file.rewind
      post documents_path, params: { document: { title: "SVG", source_type: "other", direction: "unknown", attachments: [Rack::Test::UploadedFile.new(file.path, "image/svg+xml")] }, save_only: "1" }
    end
    assert_response :unprocessable_entity
    assert_empty @wedding.documents

    with_document_limit(:MAX_ATTACHMENT_BYTES, 1) do
      Tempfile.create(["架空", ".png"]) do |file|
        file.binmode
        file.write(PNG_1X1)
        file.rewind
        post documents_path, params: { document: { title: "大きすぎる架空画像", source_type: "other", direction: "unknown", attachments: [Rack::Test::UploadedFile.new(file.path, "image/png")] }, save_only: "1" }
      end
      assert_response :unprocessable_entity
    end

    Tempfile.create(["架空壊れ", ".png"]) do |file|
      file.write("これは画像ではありません")
      file.rewind
      post documents_path, params: { document: { title: "壊れた画像", source_type: "other", direction: "unknown", attachments: [Rack::Test::UploadedFile.new(file.path, "image/png")] }, save_only: "1" }
    end
    assert_response :unprocessable_entity

    Tempfile.create(["架空PDF", ".pdf"]) do |file|
      file.write("%PDF-1.7\nこれは壊れたPDFです")
      file.rewind
      post documents_path, params: { document: { title: "壊れたPDF", source_type: "other", direction: "unknown", attachments: [Rack::Test::UploadedFile.new(file.path, "application/pdf")] }, save_only: "1" }
    end
    assert_response :unprocessable_entity
  end

  test "accepts a valid PDF and rejects encrypted or over-page PDFs" do
    Tempfile.create(["架空有効PDF", ".pdf"]) do |file|
      file.binmode
      file.write(pdf_fixture)
      file.rewind
      post documents_path, params: { document: { title: "有効な架空PDF", source_type: "other", direction: "unknown", attachments: [Rack::Test::UploadedFile.new(file.path, "application/pdf")] }, save_only: "1" }
    end
    assert_response :redirect

    with_document_limit(:MAX_PDF_PAGES, 0) do
      Tempfile.create(["架空ページ超過", ".pdf"]) do |file|
        file.binmode
        file.write(pdf_fixture(marker: "page-limit"))
        file.rewind
        post documents_path, params: { document: { title: "ページ超過", source_type: "other", direction: "unknown", attachments: [Rack::Test::UploadedFile.new(file.path, "application/pdf")] }, save_only: "1" }
      end
      assert_response :unprocessable_entity
    end

    Tempfile.create(["架空暗号化PDF", ".pdf"]) do |file|
      file.binmode
      file.write(pdf_fixture(encrypted: true, marker: "encrypted"))
      file.rewind
      post documents_path, params: { document: { title: "暗号化PDF", source_type: "other", direction: "unknown", attachments: [Rack::Test::UploadedFile.new(file.path, "application/pdf")] }, save_only: "1" }
    end
    assert_response :unprocessable_entity
  end

  test "change operation contract rejects unknown fields and applies selected operations atomically" do
    document = @wedding.documents.create!(title: "架空本文資料", original_text: "会場へ確認する", source_type: "meeting", direction: "incoming")
    change_set = @wedding.change_sets.create!(document: document, operation_key: "架空変更束")
    operation = change_set.change_operations.build(operation_key: "架空項目", action: "create", entity_type: "PlanningItem",
      attributes_data: { "_key" => "item-1", "title" => "架空演出", "category" => "other", "unexpected" => "拒否" },
      evidence_data: [{ "document_id" => document.id, "quote" => "会場へ確認する" }], depends_on_data: [], uncertainties_data: [])
    refute operation.valid?
    assert_includes operation.errors[:attributes_data], "許可されていない項目があります"

    operation.attributes_data.delete("unexpected")
    operation.save!
    option = change_set.change_operations.create!(operation_key: "架空候補", action: "create", entity_type: "PlanningOption",
      attributes_data: { "title" => "架空案", "planning_item_key" => "item-1" }, evidence_data: [], depends_on_data: ["架空項目"], uncertainties_data: [])
    ChangeSet::Apply.call(change_set: change_set, operation_ids: [operation.id, option.id])
    assert_equal "applied", change_set.reload.state
    assert_equal "架空案", @wedding.planning_items.sole.planning_options.sole.title
    ChangeSet::Apply.call(change_set: change_set, operation_ids: [operation.id, option.id])
    assert_equal 1, @wedding.planning_items.count
  end

  test "source links are wedding and attachment scoped and survive document deletion as task provenance" do
    document = @wedding.documents.create!(title: "架空出典資料", original_text: "架空の確認文", source_type: "meeting", direction: "incoming")
    task = @wedding.tasks.create!(origin: "manual", title: "架空出典タスク")
    link = SourceLink.new(wedding: @wedding, document: document, target_type: "Task", target_id: task.id, quote: "架空の確認文")
    assert link.valid?
    link.save!
    foreign = create_wedding
    refute SourceLink.new(wedding: foreign, document: document, target_type: "Task", target_id: task.id).valid?

    document.attachments.attach(io: StringIO.new(PNG_1X1), filename: "根拠.png", content_type: "image/png")
    foreign_document = foreign.documents.create!(title: "別Wedding資料", original_text: "別本文", source_type: "meeting", direction: "incoming")
    foreign_document.attachments.attach(io: StringIO.new(PNG_1X1), filename: "別根拠.png", content_type: "image/png")
    refute SourceLink.new(wedding: @wedding, document: document, target_type: "Task", target_id: task.id,
      attachment: foreign_document.attachments.attachments.sole).valid?

    document.destroy!
    assert task.reload.persisted?
    assert_equal document.id, task.source_details["document_id"]
    assert_equal document.title, task.source_details["title"]
    assert_equal "meeting", task.source_details["source_type"]
    refute SourceLink.where(target_type: "Task", target_id: task.id).exists?
    assert ChangeEvent.where(target_type: "Document", target_id: document.id, action: "document_deleted").exists?
  end

  test "change operation rejects forged target and invalid evidence" do
    document = @wedding.documents.create!(title: "架空根拠資料", original_text: "本文にない引用", source_type: "meeting", direction: "incoming")
    other = create_wedding
    item = other.planning_items.create!(title: "別Wedding項目", category: "other")
    change_set = @wedding.change_sets.create!(document: document, operation_key: "架空不正束")
    operation = change_set.change_operations.create!(operation_key: "偽ID", action: "update", entity_type: "PlanningItem", target_id: item.id,
      expected_lock_version: item.lock_version, attributes_data: { "title" => "書き換え" }, evidence_data: [{ "document_id" => document.id, "quote" => "一致しない" }], depends_on_data: [], uncertainties_data: [])
    assert_raises(ChangeSet::Apply::InvalidEvidence) { ChangeSet::Apply.call(change_set: change_set, operation_ids: [operation.id]) }
    assert_equal "別Wedding項目", item.reload.title
  end

  test "document enforces attachment count and total size limits" do
    files = 11.times.map do |index|
      file = Tempfile.new(["架空#{index}", ".png"])
      file.binmode
      file.write(PNG_1X1)
      file.rewind
      file
    end
    uploads = files.map { |file| Rack::Test::UploadedFile.new(file.path, "image/png") }
    post documents_path, params: { document: { title: "添付上限", source_type: "other", direction: "unknown", attachments: uploads }, save_only: "1" }
    assert_response :unprocessable_entity
  ensure
    files&.each { |file| file.close! }
  end

  test "change operation conflict rolls back every selected operation" do
    document = @wedding.documents.create!(title: "架空競合資料", original_text: "候補を確認する", source_type: "meeting", direction: "incoming")
    item = @wedding.planning_items.create!(title: "既存項目", category: "other")
    change_set = @wedding.change_sets.create!(document: document, operation_key: "架空競合束")
    create_operation = change_set.change_operations.create!(operation_key: "作成", action: "create", entity_type: "PlanningItem",
      attributes_data: { "title" => "ロールバック項目", "category" => "other" }, evidence_data: [], depends_on_data: [], uncertainties_data: [])
    update_operation = change_set.change_operations.create!(operation_key: "更新", action: "update", entity_type: "PlanningItem", target_id: item.id,
      expected_lock_version: item.lock_version + 1, attributes_data: { "title" => "更新されない" }, evidence_data: [], depends_on_data: [], uncertainties_data: [])

    assert_raises(ChangeSet::Apply::Conflict) { ChangeSet::Apply.call(change_set: change_set, operation_ids: [create_operation.id, update_operation.id]) }
    refute @wedding.planning_items.exists?(title: "ロールバック項目")
    assert_equal "既存項目", item.reload.title
    assert_equal "failed", change_set.reload.state
  end

  test "change operations use dependency order, create source links, and reject cycles" do
    document = @wedding.documents.create!(title: "架空依存資料", original_text: "候補を確認する", source_type: "meeting", direction: "incoming")
    change_set = @wedding.change_sets.create!(document: document, operation_key: "架空依存束")
    child = change_set.change_operations.create!(operation_key: "子", action: "create", entity_type: "PlanningOption",
      attributes_data: { "_key" => "planning-child", "title" => "架空子候補", "planning_item_key" => "planning-parent" },
      evidence_data: [{ "document_id" => document.id, "quote" => "候補を確認する" }], depends_on_data: ["親"], uncertainties_data: [])
    parent = change_set.change_operations.create!(operation_key: "親", action: "create", entity_type: "PlanningItem",
      attributes_data: { "_key" => "planning-parent", "title" => "架空親項目", "category" => "other" },
      evidence_data: [{ "document_id" => document.id, "quote" => "候補を確認する" }], depends_on_data: [], uncertainties_data: [])

    ChangeSet::Apply.call(change_set: change_set, operation_ids: [child.id, parent.id])
    assert_equal 1, @wedding.source_links.where(target_type: "PlanningItem").count
    assert_equal 1, @wedding.source_links.where(target_type: "PlanningOption").count

    cyclic = @wedding.change_sets.create!(document: document, operation_key: "架空循環束")
    first = cyclic.change_operations.create!(operation_key: "循環A", action: "create", entity_type: "PlanningItem",
      attributes_data: { "title" => "作られないA", "category" => "other" }, evidence_data: [], depends_on_data: ["循環B"], uncertainties_data: [])
    second = cyclic.change_operations.create!(operation_key: "循環B", action: "create", entity_type: "PlanningItem",
      attributes_data: { "title" => "作られないB", "category" => "other" }, evidence_data: [], depends_on_data: ["循環A"], uncertainties_data: [])
    assert_raises(ChangeSet::Apply::InvalidOperation) { ChangeSet::Apply.call(change_set: cyclic, operation_ids: [first.id, second.id]) }
    refute @wedding.planning_items.exists?(title: "作られないA")
    assert_equal "failed", cyclic.reload.state
  end

  test "AI-created records retain evidence and GiftAssignment always has an estimate budget item" do
    document = @wedding.documents.create!(title: "架空AI資料", original_text: "候補を登録する", source_type: "meeting", direction: "incoming")
    household = @wedding.households.create!(name: "架空世帯")
    gift_set = @wedding.gift_sets.create!(name: "架空引出物")
    gift_set.gift_set_items.create!(name: "架空品", unit_price_yen: 12_000)
    change_set = @wedding.change_sets.create!(document: document, operation_key: "架空AI割当")
    assignment = change_set.change_operations.create!(operation_key: "割当", action: "create", entity_type: "GiftAssignment",
      attributes_data: { "household_id" => household.id, "gift_set_id" => gift_set.id, "quantity" => 1, "included" => true },
      evidence_data: [{ "document_id" => document.id, "quote" => "候補を登録する" }], depends_on_data: [], uncertainties_data: [])
    task = change_set.change_operations.create!(operation_key: "AIタスク", action: "create", entity_type: "Task",
      attributes_data: { "title" => "架空AIタスク", "origin" => "ai", "category" => "other" },
      evidence_data: [{ "document_id" => document.id, "quote" => "候補を登録する" }], depends_on_data: [], uncertainties_data: [])

    ChangeSet::Apply.call(change_set: change_set, operation_ids: [assignment.id, task.id])
    saved_assignment = @wedding.gift_assignments.find_by!(household_id: household.id)
    assert_equal 12_000, saved_assignment.budget_item.amount_yen
    assert_equal "estimate", saved_assignment.budget_item.certainty
    assert_equal "gift_assignment", saved_assignment.budget_item.source_kind
    saved_task = @wedding.tasks.order(:id).last
    assert @wedding.source_links.where(target_type: "Task", target_id: saved_task.id).exists?
  end

  test "MusicDetail created by ChangeSet belongs to the same wedding" do
    item = @wedding.planning_items.create!(title: "架空BGM項目", category: "music")
    option = item.planning_options.create!(wedding: @wedding, title: "架空BGM候補")
    document = @wedding.documents.create!(title: "架空BGM資料", original_text: "音楽を確認する", source_type: "meeting", direction: "incoming")
    change_set = @wedding.change_sets.create!(document: document, operation_key: "架空BGM変更")
    operation = change_set.change_operations.create!(operation_key: "BGM", action: "create", entity_type: "MusicDetail",
      attributes_data: { "planning_option_id" => option.id, "selected_track" => "架空曲" }, evidence_data: [], depends_on_data: [], uncertainties_data: [])

    ChangeSet::Apply.call(change_set: change_set, operation_ids: [operation.id])
    assert_equal @wedding.id, option.reload.music_detail.wedding_id
  end

  test "storage configuration nests S3 options and every AI allowlist field is a real column" do
    source = ERB.new(File.read(Rails.root.join("config/storage.yml"))).result
    config = YAML.safe_load(source)
    assert_equal true, config.fetch("supabase").fetch("force_path_style")
    refute config.key?("force_path_style")
    assert_empty ChangeOperation.allowlist_attribute_issues
    refute Rails.application.routes.routes.any? { |route| route.path.spec.to_s.include?("/rails/active_storage") }
    get new_document_path
    assert_select "button[type='submit'][name='organize'][value='1']", text: "保存してAI整理する →"
    get document_path(@wedding.documents.create!(title: "架空表示資料", original_text: "表示を確認する", source_type: "meeting", direction: "incoming"))
    assert_select "button[disabled]", text: "AI整理は未設定です"
  end

  private

  def with_document_limit(name, value)
    original = Document.const_get(name)
    Document.send(:remove_const, name)
    Document.const_set(name, value)
    yield
  ensure
    Document.send(:remove_const, name)
    Document.const_set(name, original)
  end

  def pdf_fixture(encrypted: false, marker: "valid")
    objects = [
      "<< /Type /Catalog /Pages 2 0 R /Producer (#{marker}) >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>"
    ]
    objects << "<< /Filter /Standard /V 1 /R 2 /O <00000000000000000000000000000000> /U <00000000000000000000000000000000> /P -4 >>" if encrypted
    body = +"%PDF-1.4\n"
    offsets = [0]
    objects.each_with_index do |object, index|
      offsets << body.bytesize
      body << "#{index + 1} 0 obj\n#{object}\nendobj\n"
    end
    xref_offset = body.bytesize
    body << "xref\n0 #{objects.length + 1}\n0000000000 65535 f \n"
    offsets.drop(1).each { |offset| body << format("%010d 00000 n \n", offset) }
    encrypt_clause = encrypted ? " /Encrypt #{objects.length} 0 R" : ""
    body << "trailer\n<< /Size #{objects.length + 1} /Root 1 0 R#{encrypt_clause} >>\nstartxref\n#{xref_offset}\n%%EOF\n"
    body
  end
end
