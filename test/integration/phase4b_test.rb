require "test_helper"
require "zip"
require "csv"

class Phase4bTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_owner
    @wedding = create_wedding(@owner)
    sign_in(@owner)
  end

  test "task filters, gantt, and bulk update stay within the wedding" do
    first = @wedding.tasks.create!(title: "架空 会場確認", status: "todo", assignee: "person_a", category: "venue",
      starts_on: Date.current, due_on: Date.current + 2.days, origin: "manual")
    second = @wedding.tasks.create!(title: "架空 期限だけ", status: "todo", assignee: "person_b", category: "guest",
      due_on: Date.current + 1.day, origin: "manual")
    foreign = create_wedding.tasks.create!(title: "Wedding外", status: "todo", assignee: "unknown", category: "venue", origin: "manual")

    get tasks_path(q: "架空", category: "venue")
    assert_response :success
    assert_includes response.body, first.title
    refute_includes response.body, second.title
    refute_includes response.body, foreign.title

    get tasks_path(view: "gantt", range: "week", anchor: Date.current.iso8601)
    assert_response :success
    assert_includes response.body, "gantt-bar"
    assert_includes response.body, "期限だけ"
    assert_select "[data-gantt-board][data-range-start]", count: 1
    assert_select ".gantt-interaction-note", text: /ドラッグして日程を移動/
    assert_select ".gantt-bar[draggable='true']", minimum: 1

    post bulk_preview_tasks_path, params: { task_ids: [first.id, second.id] }
    assert_response :success
    assert_includes response.body, "2件"
    post bulk_update_tasks_path, params: {
      items: { first.id => first.lock_version, second.id => second.lock_version },
      status: "doing", assignee: "", category: ""
    }
    assert_redirected_to tasks_path
    assert_equal %w[doing doing], [first.reload.status, second.reload.status]
    assert_equal 2, @wedding.change_events.where(action: "task_bulk_updated").count

    post bulk_update_tasks_path, params: { items: { foreign.id => foreign.lock_version }, status: "done" }
    assert_redirected_to tasks_path
    assert_equal "todo", foreign.reload.status
  end

  test "gantt orders dated tasks by the agreed buckets and keeps undated tasks separate" do
    today = Date.current
    overdue_old = @wedding.tasks.create!(title: "架空期限超過古", status: "todo", assignee: "unknown", category: "other",
      due_on: today - 5.days, origin: "manual")
    overdue_new = @wedding.tasks.create!(title: "架空期限超過新", status: "todo", assignee: "unknown", category: "other",
      due_on: today - 1.day, origin: "manual")
    active_doing = @wedding.tasks.create!(title: "架空進行中", status: "doing", assignee: "unknown", category: "other",
      starts_on: today - 1.day, due_on: today + 3.days, origin: "manual")
    active_todo = @wedding.tasks.create!(title: "架空未着手", status: "todo", assignee: "unknown", category: "other",
      starts_on: today - 1.day, due_on: today + 3.days, origin: "manual")
    soon = @wedding.tasks.create!(title: "架空7日以内", status: "todo", assignee: "unknown", category: "other",
      due_on: today + 6.days, origin: "manual")
    later = @wedding.tasks.create!(title: "架空それ以降", status: "todo", assignee: "unknown", category: "other",
      due_on: today + 8.days, origin: "manual")
    undated = @wedding.tasks.create!(title: "架空日付なし", status: "todo", assignee: "unknown", category: "other", origin: "manual")

    get tasks_path(view: "gantt", range: "month", anchor: today.iso8601)

    assert_response :success
    positions = [overdue_old, overdue_new, active_doing, active_todo, soon, later].map { |task| response.body.index(task.title) }
    assert_equal positions.sort, positions
    assert_operator response.body.index(active_doing.title), :<, response.body.index(active_todo.title)
    assert_operator response.body.index(later.title), :<, response.body.index(undated.title)
    assert_select ".undated-list", count: 1
    assert_select ".undated-list", text: /架空日付なし/
  end

  test "monthly gantt spans the surrounding weeks across month boundaries" do
    starts_in_september = @wedding.tasks.create!(title: "架空9月末から10月", status: "todo", assignee: "unknown", category: "other",
      starts_on: Date.new(2026, 9, 28), due_on: Date.new(2026, 10, 3), origin: "manual")
    starts_before_month = @wedding.tasks.create!(title: "架空8月末から9月", status: "todo", assignee: "unknown", category: "other",
      starts_on: Date.new(2026, 8, 30), due_on: Date.new(2026, 9, 2), origin: "manual")

    get tasks_path(view: "gantt", range: "month", anchor: Date.new(2026, 9, 15).iso8601)

    assert_response :success
    assert_includes response.body, "8/31〜10/4を表示"
    assert_select ".gantt-board.days-35", count: 1
    assert_select ".gantt-header .month-start", count: 2
    assert_select ".gantt-bar.column-29.span-6", count: 1
    assert_select ".gantt-bar.column-1.span-3", count: 1
    assert_select "[aria-label='前の月']", count: 1
    assert_select "[aria-label='次の月']", count: 1
    assert_includes response.body, "anchor=2026-08-01"
    assert_includes response.body, "anchor=2026-10-01"
    assert_includes response.body, starts_in_september.title
    assert_includes response.body, starts_before_month.title
  end

  test "stale bulk update rolls every task back" do
    first = @wedding.tasks.create!(title: "架空 一", origin: "manual")
    second = @wedding.tasks.create!(title: "架空 二", origin: "manual")
    assert_raises(ActiveRecord::StaleObjectError) do
      TaskBulkUpdate.apply!(@wedding, { first.id => first.lock_version, second.id => second.lock_version + 1 },
        { status: "doing" }, actor: @owner)
    end
    assert_equal %w[todo todo], [first.reload.status, second.reload.status]
    assert_equal 0, @wedding.change_events.where(action: "task_bulk_updated").count
  end

  test "export separates related tables, adds BOM, and neutralizes formulas" do
    household = @wedding.households.create!(code: "H-1", name: "=架空世帯")
    set = @wedding.gift_sets.create!(name: "架空セット")
    item = set.gift_set_items.create!(kind: "gift", name: "+架空品", unit_price_yen: 3_000)
    assignment = @wedding.gift_assignments.create!(household: household, gift_set: set, quantity: 2)
    planning = @wedding.planning_items.create!(title: "架空演出", category: "production")
    option = planning.planning_options.create!(wedding: @wedding, title: "架空案", status: "considering")
    option.create_music_detail!(wedding: @wedding, selected_track: "架空曲")
    @wedding.documents.create!(title: "架空資料", source_type: "email", original_text: "本文")
    create_wedding.households.create!(code: "OUT", name: "Wedding外")

    entries = {}
    Zip::File.open_buffer(WeddingCsvExport.call(@wedding)) do |zip|
      zip.each { |entry| entries[entry.name] = entry.get_input_stream.read.force_encoding(Encoding::UTF_8) }
    end
    assert_equal WeddingCsvExport::TABLES.keys.map { |name| "#{name}.csv" }.sort, entries.keys.sort
    assert entries.values.all? { |data| data.start_with?("\uFEFF") }
    refute entries.keys.any? { |name| name.include?("attachment") }

    households = CSV.parse(entries.fetch("households.csv").delete_prefix("\uFEFF"), headers: true)
    assert_equal "'=架空世帯", households.first["name"]
    refute_includes entries.fetch("households.csv"), "Wedding外"
    gift_items = CSV.parse(entries.fetch("gift_set_items.csv").delete_prefix("\uFEFF"), headers: true)
    assert_equal item.id.to_s, gift_items.first["id"]
    assert_equal "'+架空品", gift_items.first["name"]
    gift_assignments = CSV.parse(entries.fetch("gift_assignments.csv").delete_prefix("\uFEFF"), headers: true)
    assert_equal assignment.id.to_s, gift_assignments.first["id"]
    assert_equal "H-1", households.first["code"]
    music = CSV.parse(entries.fetch("music_details.csv").delete_prefix("\uFEFF"), headers: true)
    assert_equal "架空曲", music.first["selected_track"]
  end

  test "dashboard renders management totals" do
    @wedding.guests.create!(name: "架空ゲスト", attendance: "attending")
    @wedding.budget_items.create!(direction: "expense", category: "venue", title: "架空費用", amount_yen: 100_000, certainty: "confirmed")
    get root_path
    assert_response :success
    assert_includes response.body, "お金の見通し"
    assert_includes response.body, "ダッシュボード"
    assert_includes response.body, "100,000"
    refute_includes response.body, "ふたりの結婚式"
  end
end
