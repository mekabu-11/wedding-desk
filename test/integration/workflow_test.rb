require "test_helper"
class WorkflowTest < ActionDispatch::IntegrationTest
  test "login, onboarding, sample, acceptance, edit and deletion complete the flow" do
    owner = create_owner
    get root_path
    assert_redirected_to new_session_path
    sign_in(owner)
    get root_path
    assert_redirected_to new_wedding_path
    post wedding_path, params: { wedding: { name: "私たちの結婚式", wedding_date: "2026-10-25", venue_name: "サンプル会場" } }
    assert_redirected_to root_path
    perform_enqueued_jobs { post sample_documents_path }
    doc = owner.reload.wedding.documents.first
    assert_redirected_to document_path(doc)
    get document_path(doc)
    assert_response :success
    assert_select "h2", text: "やることの候補"
    assert_select "input[name='confirmed']", count: 2
    candidate = doc.candidates.first
    patch document_candidate_path(doc, candidate), params: { decision: "accept", confirmed: "1", task: acceptance_attributes(candidate) }
    assert_equal 1, owner.wedding.tasks.count
    task = candidate.reload.task
    get tasks_path
    assert_response :success
    assert_includes response.body, task.title
    patch task_path(task), params: { task: { title: "手動で修正", status: "done", lock_version: task.lock_version } }
    assert_equal "done", task.reload.status
    delete document_path(doc), params: { confirm_delete: "1" }
    assert_redirected_to documents_path
    assert_equal 1, owner.wedding.tasks.count
    assert_equal 0, owner.wedding.documents.count
    assert_nil task.reload.candidate
    assert task.source_details["source_deleted_at"].present?
    get edit_task_path(task)
    assert_response :success
    assert_includes response.body, "元資料は削除済みです"
  end

  test "owner can add a second login that shares the same wedding" do
    owner = create_owner
    wedding = create_wedding(owner)
    wedding.tasks.create!(origin: "manual", title: "共有されるタスク")
    sign_in(owner)

    post membership_path, params: { member: {
      email: "partner@example.test",
      password: "partner-password-12345",
      password_confirmation: "partner-password-12345"
    } }
    assert_redirected_to edit_wedding_path
    partner = User.find_by!(email: "partner@example.test")
    assert_equal wedding, partner.wedding
    assert_equal 2, wedding.memberships.count

    delete session_path
    sign_in(partner, password: "partner-password-12345")
    get tasks_path
    assert_response :success
    assert_includes response.body, "共有されるタスク"
  end

  test "owner can set a private cover photo that appears on the dashboard" do
    owner = create_owner
    wedding = create_wedding(owner)
    sign_in(owner)

    photo = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")
    Tempfile.create(["トップ写真", ".png"]) do |file|
      file.binmode
      file.write(photo)
      file.rewind
      patch wedding_path, params: { wedding: { name: wedding.name, cover_photo: Rack::Test::UploadedFile.new(file.path, "image/png") } }
    end

    assert_redirected_to root_path
    assert wedding.reload.cover_photo.attached?
    get root_path
    assert_response :success
    assert_includes response.body, wedding_cover_photo_path

    get wedding_cover_photo_path
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal photo, response.body

    perform_enqueued_jobs do
      patch wedding_path, params: { wedding: { name: wedding.name, remove_cover_photo: "1" } }
    end
    assert_redirected_to root_path
    refute wedding.reload.cover_photo.attached?

    other = create_wedding
    sign_in(other.users.first)
    get wedding_cover_photo_path
    assert_response :not_found
  end

  test "dashboard recent changes explain the record and action in Japanese" do
    owner = create_owner
    wedding = create_wedding(owner)
    guest = wedding.guests.create!(name: "佐藤 花子", side: "unknown", age_group: "adult", attendance: "unanswered")
    ChangeEvent.create!(wedding: wedding, actor: owner, target: guest, action: "guest_attendance_changed",
      before: { attendance: "unanswered" }.to_json, after: { attendance: "attending" }.to_json, source: "guest")
    sign_in(owner)

    get root_path
    assert_response :success
    assert_includes response.body, "佐藤 花子"
    assert_includes response.body, "招待 / 出席"
    assert_includes response.body, "出欠を出席に変更"
    assert_includes response.body, "出欠：未回答 → 出席"
    refute_includes response.body, "Guest #"
    refute_includes response.body, "guest_attendance_changed"
  end

  test "theme control lives in wedding settings" do
    owner = create_owner
    create_wedding(owner)
    sign_in(owner)

    get root_path
    assert_response :success
    assert_select "[data-theme-toggle]", count: 0

    get edit_wedding_path
    assert_response :success
    assert_select "[data-theme-toggle]", count: 1
  end

  test "only the owner can add a member and a wedding is limited to two users" do
    owner = create_owner
    wedding = create_wedding(owner)
    partner = User.create!(email: "partner-guard@example.test", password: "partner-password-12345")
    wedding.memberships.create!(user: partner, role: "editor")

    sign_in(partner, password: "partner-password-12345")
    post membership_path, params: { member: {
      email: "third@example.test",
      password: "third-password-12345",
      password_confirmation: "third-password-12345"
    } }
    assert_redirected_to edit_wedding_path
    assert_nil User.find_by(email: "third@example.test")
    assert_equal 2, wedding.memberships.count
  end

  test "another owner's documents candidates tasks and retries are inaccessible" do
    owner = create_owner
    create_wedding(owner)
    other = sample_document
    analyze_sample(other)
    candidate = other.candidates.first
    task = ReviewCandidate.call(candidate, decision: "accept", attributes: acceptance_attributes(candidate))
    sign_in(owner)
    get document_path(other)
    assert_response :not_found
    post retry_analysis_document_path(other)
    assert_response :not_found
    patch document_candidate_path(other, candidate), params: { decision: "reject" }
    assert_response :not_found
    get edit_task_path(task)
    assert_response :not_found
    patch task_path(task), params: { task: { status: "done" } }
    assert_response :not_found
    delete document_path(other), params: { confirm_delete: "1" }
    assert_response :not_found
    assert_equal "todo", task.reload.status
  end

  test "user cannot force wedding ownership or sample provider from form" do
    owner = create_owner
    own_wedding = create_wedding(owner)
    other = create_wedding
    sign_in(owner)
    post documents_path, params: { document: { wedding_id: other.id, sample: true, source_type: "email", direction: "incoming", original_text: "一般の本文" } }
    doc = own_wedding.documents.last
    assert doc
    refute doc.sample?
    assert_nil doc.latest_run
  end

  test "accepting requires explicit original confirmation and deletion requires confirmation" do
    owner = create_owner
    doc = sample_document(create_wedding(owner))
    analyze_sample(doc)
    sign_in(owner)
    candidate = doc.candidates.first
    patch document_candidate_path(doc, candidate), params: { decision: "accept", task: acceptance_attributes(candidate) }
    assert_equal 0, Task.count
    delete document_path(doc)
    assert Document.exists?(doc.id)
  end

  test "repeated submission resolves to existing document without more runs" do
    owner = create_owner
    wedding = create_wedding(owner)
    sign_in(owner)
    data = { document: { source_type: "line", direction: "incoming", original_text: "提出をお願いします。" } }
    2.times { post documents_path, params: data }
    assert_equal 1, wedding.documents.count
    assert_equal 0, wedding.documents.first.analysis_runs.count
  end

  test "HTML in original and AI output is escaped" do
    owner = create_owner
    doc = create_wedding(owner).documents.create!(title: "<script>alert(1)</script>", source_type: "email", original_text: "<img src=x onerror=alert(1)>")
    sign_in(owner)
    get document_path(doc)
    assert_response :success
    assert_select "script:not([src])", count: 0
    assert_select "img[onerror]", count: 0
    assert_includes response.body, "&lt;img"
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "invalid credentials fail without creating authenticated session" do
    owner = create_owner
    post session_path, params: { email: owner.email, password: "wrong" }
    assert_response :unprocessable_entity
    get root_path
    assert_redirected_to new_session_path
  end
  test "forged form submissions are rejected when CSRF protection is active" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    owner = create_owner
    create_wedding(owner)
    get new_session_path
    token = css_select("input[name='authenticity_token']").first["value"]
    post session_path, params: { email: owner.email, password: "test-password-12345", authenticity_token: token }
    assert_redirected_to root_path
    post documents_path, params: { document: { source_type: "email", original_text: "forged" } }
    assert_response :unprocessable_entity
    assert_equal 0, owner.wedding.documents.count
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

end
