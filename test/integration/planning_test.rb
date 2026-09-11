require "test_helper"

class PlanningTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_owner
    @wedding = create_wedding(@owner)
    sign_in(@owner)
  end

  test "planning CRUD, candidate selection and optional cost links are available in the app" do
    post planning_items_path, params: { planning_item: { title: "架空演出", category: "production", notes: "架空メモ" } }
    assert_redirected_to planning_item_path(@wedding.planning_items.last)
    item = @wedding.planning_items.last
    post planning_item_planning_options_path(item), params: { planning_option: { title: "架空案A", status: "selected", reference_price_yen: 500_000 } }
    option_a = item.planning_options.last
    assert_equal "draft", option_a.reload.status
    post planning_item_planning_options_path(item), params: { planning_option: { title: "架空案B", description: "架空説明" } }
    option_b = item.planning_options.last
    patch planning_option_path(option_b), params: { planning_option: { status: "considering", lock_version: option_b.lock_version } }
    assert_equal "considering", option_b.reload.status
    budget = @wedding.budget_items.create!(direction: "expense", category: "production", title: "架空会場費", amount_yen: 500_000)
    post planning_cost_links_path, params: { planning_item_id: item.id, budget_item_id: budget.id }
    post select_planning_option_path(option_a)
    assert_redirected_to planning_item_path(item)
    assert_equal "selected", option_a.reload.status
    assert_equal 1, item.planning_cost_links.count
    assert_equal @owner, ChangeEvent.for_target(option_a).first.actor
    get planning_item_path(item)
    assert_includes response.body, "planning_option_selected"
    duplicate_selected = item.planning_options.new(wedding: @wedding, title: "架空重複採用", status: "selected")
    refute duplicate_selected.valid?
    assert_includes duplicate_selected.errors[:status], "1項目につき採用は1件までです"
    post select_planning_option_path(option_b)
    assert_equal "rejected", option_a.reload.status
    assert_equal "selected", option_b.reload.status
    assert_equal [budget.id], item.planning_cost_links.reload.pluck(:budget_item_id)
    patch planning_option_path(option_b), params: { planning_option: { title: "架空案B更新", status: "selected", lock_version: option_b.lock_version } }
    assert_redirected_to planning_item_path(item)
    assert_equal "selected", option_b.reload.status
  end

  test "planning index filters by candidate status" do
    selected_item = @wedding.planning_items.create!(title: "架空採用項目", category: "production")
    selected_item.planning_options.create!(wedding: @wedding, title: "架空採用候補", status: "selected")
    @wedding.planning_items.create!(title: "架空下書き項目", category: "music").planning_options.create!(wedding: @wedding, title: "架空下書き候補", status: "draft")

    get planning_items_path(status: "selected")
    assert_response :success
    assert_includes response.body, "架空採用項目"
    refute_includes response.body, "架空下書き項目"
    assert_select "select[name='status']", count: 1
  end

  test "automatic estimate update rolls back amount when history recording fails" do
    guest = @wedding.guests.create!(name: "架空原子性 太郎", attendance: "pending")
    budget = @wedding.budget_items.create!(direction: "expense", category: "other", title: "架空原子性費", certainty: "estimate",
      calculation_mode: "quantity", quantity_basis: "attending_guests", unit_price: 10_000)
    original_amount = budget.amount_yen
    original_lock_version = budget.lock_version
    invalid_event = ChangeEvent.new

    original_record = ChangeEvent.method(:record!)
    record_or_fail = lambda do |**kwargs|
      raise ActiveRecord::RecordInvalid, invalid_event if kwargs.fetch(:target).is_a?(BudgetItem)

      original_record.call(**kwargs)
    end
    guest.update_columns(attendance: "attending")
    ChangeEvent.singleton_class.define_method(:record!, record_or_fail)
    begin
      assert_raises(ActiveRecord::RecordInvalid) do
        BudgetEstimateRecalculator.for_guest_change!(@wedding.id)
      end
    ensure
      ChangeEvent.singleton_class.define_method(:record!, original_record)
    end

    assert_equal original_amount, budget.reload.amount_yen
    assert_equal original_lock_version, budget.lock_version
  end

  test "one budget item can link to three planning items without multiplying totals" do
    budget = @wedding.budget_items.create!(direction: "expense", category: "other", title: "架空一括費用", amount_yen: 500_000)
    3.times do |index|
      item = @wedding.planning_items.create!(title: "架空関連#{index}", category: "production")
      post planning_cost_links_path, params: { planning_item_id: item.id, budget_item_id: budget.id }
      assert_redirected_to planning_item_path(item)
    end
    assert_equal 3, @wedding.planning_cost_links.count
    assert_equal 500_000, @wedding.budget_items.included.expenses.sum(:amount_yen)
  end

  test "music detail and task links are editable and scoped to the wedding" do
    item = @wedding.planning_items.create!(title: "架空入場BGM", category: "music")
    option = item.planning_options.create!(wedding: @wedding, title: "架空曲")
    post planning_option_music_detail_path(option), params: { music_detail: { scene: "入場", wish_track_a: "架空希望A", wish_track_b: "架空希望B", selected_track: "架空決定曲", artist: "架空歌手", start_offset_seconds: 12, original_text: "架空元表記" } }
    assert_redirected_to planning_item_path(item)
    assert_equal "架空決定曲", option.reload.music_detail.selected_track
    task = @wedding.tasks.create!(origin: "manual", title: "架空BGMタスク")
    post task_planning_links_path, params: { planning_item_id: item.id, task_id: task.id }
    assert_equal 1, item.reload.task_planning_links.count
    get edit_task_path(task)
    assert_select "form.related-planning-form", count: 1
    assert_select "form.related-planning-form input[type='submit'][value='追加']", count: 1
    delete task_planning_link_path(item.task_planning_links.first)
    assert_empty item.reload.task_planning_links
    get planning_item_path(item)
    assert_response :success
    assert_includes response.body, "元表記"
  end

  test "candidate selection ignores foreign cost parameters without changing links" do
    item = @wedding.planning_items.create!(title: "架空ロールバック", category: "other")
    option = item.planning_options.create!(wedding: @wedding, title: "架空採用")
    other = create_wedding
    foreign_budget = other.budget_items.create!(direction: "expense", category: "other", title: "別Wedding費用", amount_yen: 10_000)
    post select_planning_option_path(option), params: { cost_mode: "existing", budget_item_id: foreign_budget.id }
    assert_redirected_to planning_item_path(item)
    assert_equal "selected", option.reload.status
    assert_empty item.planning_cost_links
  end

  test "candidate selection does not require a cost" do
    item = @wedding.planning_items.create!(title: "架空費用未選択", category: "other")
    option = item.planning_options.create!(wedding: @wedding, title: "架空候補")

    post select_planning_option_path(option)

    assert_redirected_to planning_item_path(item)
    assert_equal "selected", option.reload.status
    assert_empty item.planning_cost_links
  end

  test "rejected candidate can return to considering" do
    item = @wedding.planning_items.create!(title: "架空候補復帰", category: "other")
    option = item.planning_options.create!(wedding: @wedding, title: "架空見送り候補", status: "considering")

    post reject_planning_option_path(option)
    assert_equal "rejected", option.reload.status

    post restore_planning_option_path(option)
    assert_redirected_to planning_item_path(item)
    assert_equal "considering", option.reload.status
    assert ChangeEvent.for_target(option).where(action: "planning_option_restored").exists?
  end

  test "candidate cost history is retained and only unpaid estimates are excluded" do
    item = @wedding.planning_items.create!(title: "架空費用履歴", category: "production")
    old_option = item.planning_options.create!(wedding: @wedding, title: "架空旧候補", reference_price_yen: 30_000)
    new_option = item.planning_options.create!(wedding: @wedding, title: "架空新候補")

    post select_planning_option_path(old_option), params: { cost_mode: "new" }
    old_budget = item.reload.planning_cost_links.first.budget_item
    assert_equal "planning_option", old_budget.source_kind
    assert_equal old_option.id, old_budget.source_id
    assert_equal 30_000, old_budget.amount_yen

    post select_planning_option_path(new_option)
    assert_equal "excluded", old_budget.reload.inclusion
    assert old_budget.reload.persisted?
    assert ChangeEvent.for_target(old_budget).where(action: "planning_option_cost_excluded").exists?

    confirmed_item = @wedding.budget_items.create!(direction: "expense", category: "production", title: "架空確定候補費",
      amount_yen: 31_000, certainty: "confirmed", source_kind: "planning_option", source_id: new_option.id)
    @wedding.planning_cost_links.create!(planning_item: item, budget_item: confirmed_item)
    replacement = item.planning_options.create!(wedding: @wedding, title: "架空三番目")
    post select_planning_option_path(replacement)
    assert_equal "included", confirmed_item.reload.inclusion
    assert ChangeEvent.for_target(replacement).where(action: "planning_option_cost_changed").exists?
  end

  test "a task and a budget item can be created from a planning item and linked immediately" do
    item = @wedding.planning_items.create!(title: "架空その場追加", category: "production")

    post tasks_path, params: { planning_item_id: item.id, task: { title: "架空関連タスク", category: "other" } }
    assert_redirected_to planning_item_path(item)
    task = @wedding.tasks.order(:id).last
    assert_equal "架空関連タスク", task.title
    assert_equal [task.id], item.reload.tasks.pluck(:id)

    post budget_items_path, params: { planning_item_id: item.id, budget_item: { direction: "expense", category: "production", title: "架空関連費用", amount_yen: 12_000 } }
    assert_redirected_to planning_item_path(item)
    budget = @wedding.budget_items.order(:id).last
    assert_equal "架空関連費用", budget.title
    assert_equal [budget.id], item.reload.budget_items.pluck(:id)
  end

  test "guest manual attendance and automatic budget changes create attributable history" do
    guest = @wedding.guests.create!(name: "架空履歴 太郎", attendance: "pending")
    budget = @wedding.budget_items.create!(direction: "expense", category: "other", title: "架空履歴費", certainty: "estimate",
      calculation_mode: "quantity", quantity_basis: "attending_guests", unit_price: 10_000)
    patch guest_path(guest), params: { guest: { attendance: "attending", lock_version: guest.lock_version } }
    assert_redirected_to guests_path(tab: "individuals")
    assert_equal @owner, ChangeEvent.for_target(guest.reload).first.actor
    event = ChangeEvent.for_target(budget).find_by(action: "budget_estimate_recalculated")
    assert_nil event.actor
    assert_equal "automatic_recalculation", event.source
    assert_equal 10_000, budget.reload.amount_yen
  end
end
