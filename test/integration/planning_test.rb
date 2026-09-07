require "test_helper"

class PlanningTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_owner
    @wedding = create_wedding(@owner)
    sign_in(@owner)
  end

  test "planning CRUD, candidate selection and cost choice are available in the app" do
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
    post select_planning_option_path(option_a), params: { cost_mode: "existing", budget_item_id: budget.id }
    assert_redirected_to planning_item_path(item)
    assert_equal "selected", option_a.reload.status
    assert_equal 1, item.planning_cost_links.count
    assert_equal @owner, ChangeEvent.for_target(option_a).first.actor
    get planning_item_path(item)
    assert_includes response.body, "planning_option_selected"
    duplicate_selected = item.planning_options.new(wedding: @wedding, title: "架空重複採用", status: "selected")
    refute duplicate_selected.valid?
    assert_includes duplicate_selected.errors[:status], "1項目につき採用は1件までです"
    post select_planning_option_path(option_b), params: { cost_mode: "none" }
    assert_equal "rejected", option_a.reload.status
    assert_equal "selected", option_b.reload.status
    assert_empty item.planning_cost_links.reload
    patch planning_option_path(option_b), params: { planning_option: { title: "架空案B更新", status: "selected", lock_version: option_b.lock_version } }
    assert_redirected_to planning_item_path(item)
    assert_equal "selected", option_b.reload.status
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
    delete task_planning_link_path(item.task_planning_links.first)
    assert_empty item.reload.task_planning_links
    get planning_item_path(item)
    assert_response :success
    assert_includes response.body, "元表記"
  end

  test "cost selection and links reject another wedding without changing state" do
    item = @wedding.planning_items.create!(title: "架空ロールバック", category: "other")
    option = item.planning_options.create!(wedding: @wedding, title: "架空採用")
    other = create_wedding
    foreign_budget = other.budget_items.create!(direction: "expense", category: "other", title: "別Wedding費用", amount_yen: 10_000)
    post select_planning_option_path(option), params: { cost_mode: "existing", budget_item_id: foreign_budget.id }
    assert_response :not_found
    assert_equal "draft", option.reload.status
    assert_empty item.planning_cost_links
    get edit_planning_item_path(other.planning_items.create!(title: "別Wedding項目", category: "other"))
    assert_response :not_found
  end

  test "existing cost selection without a budget rolls back with an explanation" do
    item = @wedding.planning_items.create!(title: "架空費用未選択", category: "other")
    option = item.planning_options.create!(wedding: @wedding, title: "架空候補")

    post select_planning_option_path(option), params: { cost_mode: "existing", budget_item_id: "" }

    assert_redirected_to planning_item_path(item)
    assert_equal "draft", option.reload.status
    assert_empty item.planning_cost_links
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
