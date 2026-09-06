require "test_helper"
class TaskPreparationTest < ActionDispatch::IntegrationTest
  test "manual create edit and ownership boundaries" do
    owner = create_owner
    wedding = create_wedding(owner)
    other = create_wedding
    sign_in(owner)
    get new_task_path
    assert_response :success
    post tasks_path, params: { task: { title: '手入力タスク', starts_on: '2026-09-01', due_on: '2026-09-10', origin: 'ai', wedding_id: other.id } }
    assert_redirected_to tasks_path
    task = wedding.tasks.sole
    assert_equal 'manual', task.origin
    assert_nil task.candidate
    get edit_task_path(task)
    assert_response :success
    assert_includes response.body, '手動で追加'
    patch task_path(task), params: { task: { starts_on: '2026-09-11' } }
    assert_response :unprocessable_entity
    assert_equal Date.new(2026,9,1), task.reload.starts_on
    outsider = other.tasks.create!(origin: 'manual', title: '別の結婚式')
    get edit_task_path(outsider)
    assert_response :not_found
  end
  test "upload preview confirm and duplicate confirmation" do
    owner = create_owner
    wedding = create_wedding(owner)
    row = {title: '<script>架空</script>', status_raw: '完了', assignee_raw: '共同', source_file: '架空.xlsx', source_sheet: 'タスク一覧', source_row: 5, source_sha256: 'b' * 64}
    Tempfile.create(['import', '.json']) do |f|
      f.write({format_version: 1, groups: {tasks: [row]}}.to_json)
      f.flush
      sign_in(owner)
      get new_task_import_path
      assert_response :success
      post task_imports_path, params: {file: Rack::Test::UploadedFile.new(f.path, 'application/json')}
      batch = wedding.task_imports.sole
      assert_redirected_to task_import_path(batch)
      get task_import_path(batch)
      assert_response :success
      assert_select 'script', count: 0
      assert_equal 0, wedding.tasks.count
      patch task_import_path(batch), params: {mapping: {'0' => 'both'}}
      assert_equal 0, wedding.tasks.count
      2.times { patch task_import_path(batch), params: {confirmed: '1', mapping: {'0' => 'both'}} }
      assert_equal 1, wedding.tasks.count
      assert_equal 'done', wedding.tasks.sole.status
      get edit_task_path(wedding.tasks.sole)
      assert_response :success
      assert_includes response.body, '架空.xlsx'
      get task_import_path(batch)
      assert_response :success
      sign_in(create_owner.tap { |u| create_wedding(u) })
      get task_import_path(batch)
      assert_response :not_found
      patch task_import_path(batch), params: {confirmed: '1', mapping: {'0' => 'both'}}
      assert_response :not_found
    end
  end
  test "week overlap, missing start, Japanese timezone, overdue and assignee filters" do
    owner = create_owner
    wedding = create_wedding(owner)
    sign_in(owner)
    travel_to Time.zone.local(2026,9,9,12) do
      sign_in(owner)
      wedding.tasks.create!(origin: 'manual', title: '期間が重なる', starts_on: '2026-09-01', due_on: '2026-09-30', assignee: 'self')
      wedding.tasks.create!(origin: 'manual', title: '来週開始', starts_on: '2026-09-14', due_on: '2026-09-30')
      wedding.tasks.create!(origin: 'manual', title: '日本時間月曜', due_at: Time.zone.local(2026,9,7,0,30))
      wedding.tasks.create!(origin: 'manual', title: '超過のみ', due_on: '2026-09-06')
      get tasks_path(period: 'week')
      assert_response :success
      assert_includes response.body, '期間が重なる'
      assert_includes response.body, '日本時間月曜'
      refute_includes response.body, '来週開始'
      refute_includes response.body, '超過のみ'
      get tasks_path(period: 'week', assignee: 'self')
      assert_includes response.body, '期間が重なる'
      refute_includes response.body, '日本時間月曜'
      get tasks_path(period: 'overdue')
      assert_includes response.body, '超過のみ'
      refute_includes response.body, '期間が重なる'
    end
  end
end
