require "test_helper"

class ImportTasksTest < ActiveSupport::TestCase
  def rows
    [{ "title" => "架空の準備", "notes" => "秘密のメモ", "starts_on" => "2026-09-01T00:00:00",
       "due_on" => "2026-09-10T00:00:00", "status_raw" => "進行中", "assignee_raw" => "担当A",
       "category_raw" => "独自カテゴリ", "source_file" => "架空.xlsx", "source_sheet" => "タスク一覧",
       "source_row" => 5, "source_sha256" => "a" * 64 }]
  end
  def payload(items = rows)
    { format_version: 1, groups: { tasks: items } }.to_json
  end
  test "preview makes no tasks, encrypts source, commits once and retains manual edits" do
    wedding = create_wedding
    batch = ImportTasks.prepare(wedding, payload)
    assert_equal 0, wedding.tasks.count
    assert_equal batch.id, ImportTasks.prepare(wedding, payload).id
    raw = TaskImport.connection.select_value("SELECT rows FROM task_imports WHERE id = #{batch.id}")
    refute_includes raw, "秘密のメモ"
    ImportTasks.commit(batch, { "担当A" => "self" })
    task = wedding.tasks.sole
    assert_nil task.candidate_id
    assert_equal "import", task.origin
    assert_equal "doing", task.status
    assert_equal Date.new(2026, 9, 1), task.starts_on
    assert_equal "独自カテゴリ", task.source_details['category_raw']
    assert_equal "other", task.category
    encrypted = Task.connection.select_value("SELECT title FROM tasks WHERE id = #{task.id}")
    refute_includes encrypted, "架空の準備"
    task.update!(title: "利用者による変更")
    ImportTasks.commit(batch, { "担当A" => "partner" })
    assert_equal 1, wedding.tasks.count
    changed = rows
    changed[0]['title'] = '再アップロード'
    another = ImportTasks.prepare(wedding, payload(changed))
    ImportTasks.commit(another, { "担当A" => "partner" })
    assert_equal 1, another.skipped_count
    assert_equal "利用者による変更", task.reload.title
    assert_equal "self", task.assignee
  end
  test "source keys are scoped to each wedding" do
    2.times do
      batch = ImportTasks.prepare(create_wedding, payload)
      ImportTasks.commit(batch, { "担当A" => "unknown" })
    end
    assert_equal 2, Task.count
  end
  test "invalid input never creates a preview or tasks" do
    wedding = create_wedding
    [nil, {}, 'string', [], {format_version: 1, groups: []}].each do |data|
      assert_raises(ImportTasks::Invalid) { ImportTasks.prepare(wedding, data.to_json) }
    end
    ['2026-02-30', '2026-09-10T10:00:00'].each do |date|
      bad = rows
      bad[0]['due_on'] = date
      assert_raises(ImportTasks::Invalid) { ImportTasks.prepare(wedding, payload(bad)) }
    end
    bad = rows
    bad[0]['starts_on'] = '2026-10-01'
    assert_raises(ImportTasks::Invalid) { ImportTasks.prepare(wedding, payload(bad)) }
    assert_raises(ImportTasks::Invalid) { ImportTasks.prepare(wedding, payload(rows * 2)) }
    assert_raises(ImportTasks::Invalid) { ImportTasks.prepare(wedding, payload(rows * 501)) }
    assert_raises(ImportTasks::Invalid) { ImportTasks.prepare(wedding, ' ' * (ImportTasks::MAX_BYTES + 1)) }
    assert_equal 0, TaskImport.count
    assert_equal 0, Task.count
  end
  test "mapping must be explicit and validation failure rolls back all rows" do
    items = rows
    items << rows.first.merge('source_row' => 6, 'title' => '2件目')
    batch = ImportTasks.prepare(create_wedding, payload(items))
    assert_raises(ImportTasks::Invalid) { ImportTasks.commit(batch, {}) }
    tampered = batch.rows
    tampered[1]['title'] = ''
    batch.update!(rows: tampered)
    assert_raises(ActiveRecord::RecordInvalid) { ImportTasks.commit(batch, { '担当A' => 'self' }) }
    assert_equal 0, Task.count
    assert_equal 'pending', batch.reload.status
  end
end
