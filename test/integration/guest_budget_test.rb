require "test_helper"

class GuestBudgetTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_owner
    @wedding = create_wedding(@owner)
    @rule = @wedding.cash_gift_rules.create!(label: "親族", default_amount_yen: 100_000)
    sign_in(@owner)
  end

  test "guest tabs and manual guest CRUD stay within the current wedding" do
    %w[individuals households seating gifts].each do |tab|
      get guests_path(tab: tab)
      assert_response :success
    end
    [new_guest_path, new_household_path, new_seating_table_path, new_cash_gift_rule_path,
      new_gift_set_path, new_gift_assignment_path, new_guest_gift_assignment_path, new_budget_item_path].each do |path|
      get path
      assert_response :success
    end
    assert_difference -> { @wedding.guests.count }, 1 do
      post guests_path, params: { guest: { name: "架空 花子", side: "bride", age_group: "adult", attendance: "attending" } }
    end
    assert_redirected_to guests_path(tab: "individuals")
    guest = @wedding.guests.order(:id).last
    patch guest_path(guest), params: { guest: { name: "架空 花子（更新）", lock_version: guest.lock_version } }
    assert_redirected_to guests_path(tab: "individuals")
    assert_equal "架空 花子（更新）", guest.reload.name
  end

  test "guest search runs inside the wedding before pagination" do
    household = @wedding.households.create!(code: "H-SEARCH", name: "架空検索世帯")
    household.guests.create!(name: "架空検索 太郎", attendance: "pending")
    get guests_path(tab: "individuals", q: "架空検索")
    assert_response :success
    assert_includes response.body, "架空検索 太郎"
    refute_includes response.body, "Weddingの外"
  end

  test "guest and budget indexes expose useful state filters" do
    attending = @wedding.guests.create!(name: "架空出席", attendance: "attending", side: "bride", invitation_status: "invited")
    @wedding.guests.create!(name: "架空未回答", attendance: "unanswered", side: "groom", invitation_status: "planned")
    get guests_path(tab: "individuals", attendance: "attending")
    assert_response :success
    assert_includes response.body, attending.name
    refute_includes response.body, "架空未回答"
    assert_select "select[name='attendance']", count: 1
    assert_select ".status-badge", text: "出席"

    paid = @wedding.budget_items.create!(direction: "expense", category: "venue", title: "架空完了", amount_yen: 10_000, certainty: "confirmed")
    paid.money_movements.create!(wedding: @wedding, kind: "payment", amount_yen: 10_000, occurred_on: Date.current)
    @wedding.budget_items.create!(direction: "expense", category: "venue", title: "架空未払い", amount_yen: 20_000, certainty: "estimate")
    get budget_items_path(payment_status: "completed")
    assert_response :success
    assert_includes response.body, paid.title
    refute_includes response.body, "架空未払い"
    assert_select "select[name='payment_status']", count: 1
  end

  test "guest index loads only the selected tab presentation" do
    get guests_path(tab: "seating")
    assert_response :success
    assert_includes response.body, "席次"
    refute_includes response.body, "Wedding内を検索"

    get guests_path(tab: "gifts")
    assert_response :success
    assert_includes response.body, "引き出物"
    refute_includes response.body, "Wedding内を検索"
  end

  test "foreign wedding guest and budget item ids are not accessible" do
    other = create_wedding
    guest = other.guests.create!(name: "別Weddingの架空ゲスト")
    item = other.budget_items.create!(direction: "expense", category: "other", title: "別Weddingの架空費用", amount_yen: 10_000)
    get edit_guest_path(guest)
    assert_response :not_found
    get edit_budget_item_path(item)
    assert_response :not_found
    post budget_items_path, params: { budget_item: { direction: "expense", category: "other", title: "架空費用", amount_yen: 20_000, certainty: "estimate", inclusion: "included" }, id: item.id }
    assert_equal "架空費用", @wedding.budget_items.order(:id).last.title
    assert_equal "別Weddingの架空費用", item.reload.title
  end

  test "cash gift is one BudgetItem per household and confirmed amount is preserved" do
    household = @wedding.households.create!(code: "H-001", name: "架空家", cash_gift_rule: @rule)
    2.times { household.ensure_cash_gift_budget_item! }
    assert_equal 1, @wedding.budget_items.where(source_kind: "cash_gift", source_id: household.id).count
    item = household.cash_gift_budget_item
    assert_equal 100_000, item.amount_yen
    item.update!(certainty: "confirmed", amount_yen: 120_000)
    @rule.update!(default_amount_yen: 150_000)
    household.ensure_cash_gift_budget_item!
    assert_equal 120_000, item.reload.amount_yen
  end

  test "household validation errors are not mislabeled as cash gift errors" do
    post households_path, params: { household: { code: "H-INVALID", name: "", cash_gift_rule_id: @rule.id }, cash_gift: "1" }
    assert_response :unprocessable_entity
    refute_includes response.body, "ご祝儀明細を保存できませんでした"
  end

  test "cash gift BudgetItem validation failure is explained separately" do
    post households_path, params: { household: { code: "H-LONG", name: "架空" * 75, cash_gift_rule_id: @rule.id }, cash_gift: "1" }
    assert_response :unprocessable_entity
    assert_includes response.body, "ご祝儀明細を保存できませんでした"
  end

  test "household with a cash gift item cannot be deleted" do
    household = @wedding.households.create!(code: "H-DELETE", name: "架空削除拒否", cash_gift_rule: @rule)
    household.ensure_cash_gift_budget_item!
    assert_raises(ActiveRecord::RecordNotDestroyed) { household.destroy! }
    assert household.reload.persisted?
  end

  test "movement history derives partial, refund and overpaid status" do
    item = @wedding.budget_items.create!(direction: "expense", category: "venue", title: "架空会場費", amount_yen: 220_000, certainty: "confirmed")
    get edit_budget_item_path(item)
    assert_response :success
    get new_budget_item_money_movement_path(item)
    assert_response :success
    assert_raises(ActiveRecord::RecordInvalid) do
      item.money_movements.create!(wedding: @wedding, occurred_on: Date.current, kind: "receipt", amount_yen: 1_000)
    end
    item.money_movements.create!(wedding: @wedding, occurred_on: Date.new(2026, 9, 1), kind: "payment", amount_yen: 50_000)
    assert_equal "一部", item.reload.payment_status
    item.money_movements.create!(wedding: @wedding, occurred_on: Date.new(2026, 9, 2), kind: "refund", amount_yen: 20_000)
    assert_equal 30_000, item.reload.net_movement_amount
    assert_equal 190_000, item.remaining_amount
    assert_raises(ActiveRecord::RecordInvalid) do
      item.money_movements.create!(wedding: @wedding, occurred_on: Date.current, kind: "refund", amount_yen: 31_000)
    end
    item.money_movements.create!(wedding: @wedding, occurred_on: Date.new(2026, 9, 3), kind: "payment", amount_yen: 200_000)
    assert_equal "超過・要確認", item.reload.payment_status
    duplicate_item = @wedding.budget_items.create!(direction: "expense", category: "other", title: "架空二重送信", amount_yen: 8_000)
    duplicate_params = { money_movement: { occurred_on: Date.current, kind: "payment", amount_yen: 8_000, idempotency_key: "idem-#{duplicate_item.id}" } }
    2.times do
      post budget_item_money_movements_path(duplicate_item), params: duplicate_params
      assert_redirected_to budget_items_path
    end
    assert_equal 1, duplicate_item.money_movements.count

    post budget_item_money_movements_path(duplicate_item), params: duplicate_params.deep_merge(money_movement: { amount_yen: 9_000 })
    assert_response :unprocessable_entity
    assert_includes response.body, "同じ識別子で異なる入出金内容は登録できません"
    another_item = @wedding.budget_items.create!(direction: "expense", category: "other", title: "架空別費目", amount_yen: 9_000)
    post budget_item_money_movements_path(another_item), params: duplicate_params
    assert_response :unprocessable_entity
    assert_includes response.body, "同じ識別子で異なる入出金内容は登録できません"
  end

  test "gift assignment creates one linked budget item without multiplying by household members" do
    household = @wedding.households.create!(code: "H-002", name: "架空家族")
    household.guests.create!(name: "架空 一郎", attendance: "attending")
    household.guests.create!(name: "架空 二郎", attendance: "attending")
    set = @wedding.gift_sets.create!(name: "架空セット")
    set.gift_set_items.create!(kind: "gift", name: "架空品", unit_price_yen: 5_000)
    assignment = @wedding.gift_assignments.create!(household: household, gift_set: set, quantity: 1)
    item = @wedding.budget_items.create!(direction: "expense", category: "gift", title: "架空家族の引き出物", amount_yen: assignment.total_price_yen, source_kind: "gift_assignment", source_id: assignment.id)
    assignment.update!(budget_item: item)
    assert_equal 5_000, item.amount_yen
    assert_equal 1, @wedding.budget_items.where(source_kind: "gift_assignment", source_id: assignment.id).count
  end

  test "gift assignment deletion preserves an excluded manual budget history without an orphan source" do
    household = @wedding.households.create!(code: "H-003", name: "架空解除家")
    set = @wedding.gift_sets.create!(name: "架空解除セット")
    set.gift_set_items.create!(kind: "gift", name: "架空解除品", unit_price_yen: 4_000)
    assignment = @wedding.gift_assignments.create!(household: household, gift_set: set, quantity: 1)
    item = @wedding.budget_items.create!(direction: "expense", category: "gift", title: "架空解除家の引き出物", amount_yen: 4_000,
      source_kind: "gift_assignment", source_id: assignment.id)
    assignment.update!(budget_item: item)
    delete gift_assignment_path(assignment)
    assert_redirected_to guests_path(tab: "gifts")
    assert_equal "manual", item.reload.source_kind
    assert_nil item.source_id
    assert_equal "excluded", item.inclusion
  end

  test "multiple gift set items are saved and blank rows are ignored" do
    post gift_sets_path, params: { gift_set: { name: "架空複数セット", gift_set_items_attributes: {
      "0" => { kind: "gift", name: "架空引出物", unit_price_yen: 3_000, tax_basis: "inclusive" },
      "1" => { kind: "sweet", name: "架空引菓子", unit_price_yen: 1_000, tax_basis: "inclusive" },
      "2" => { kind: "other", name: "", unit_price_yen: "", tax_basis: "unknown" }
    } } }
    assert_redirected_to guests_path(tab: "gifts")
    set = @wedding.gift_sets.find_by!(name: "架空複数セット")
    assert_equal ["架空引出物", "架空引菓子"], set.gift_set_items.order(:id).pluck(:name)
    get edit_gift_set_path(set)
    assert_response :success
    assert_includes response.body, "税率（%）"
  end

  test "gift set exclusive tax and rounding are included in total" do
    set = @wedding.gift_sets.create!(name: "架空税率セット")
    item = set.gift_set_items.create!(kind: "gift", name: "架空税率品", unit_price_yen: 1_001,
      tax_basis: "exclusive", tax_rate: 10, rounding: "ceil")
    assert_equal 1_102, item.calculated_price_yen
    assert_equal 1_102, set.total_price_yen
    item.update!(tax_basis: "inclusive")
    assert_equal 1_001, set.reload.total_price_yen
    item.assign_attributes(tax_basis: "exclusive", tax_rate: nil)
    refute item.valid?
  end

  test "gift assignment household is unique within a wedding" do
    household = @wedding.households.create!(code: "H-UNIQUE", name: "架空一世帯")
    set = @wedding.gift_sets.create!(name: "架空一意セット")
    @wedding.gift_assignments.create!(household: household, gift_set: set, quantity: 1)
    duplicate = @wedding.gift_assignments.new(household: household, gift_set: set, quantity: 1)
    refute duplicate.valid?
    assert duplicate.errors[:household_id].any?
  end

  test "tax exclusive quantity calculation applies rate and rounding while other tax bases do not add tax" do
    item = @wedding.budget_items.new(direction: "expense", category: "food", title: "架空税抜", certainty: "estimate",
      calculation_mode: "quantity", quantity_basis: "manual", manual_quantity: 3, unit_price: 1_001,
      tax_basis: "exclusive", tax_rate: 10, rounding: "floor")
    assert item.valid?
    assert_equal 3_303, item.calculated_amount
    item.rounding = "ceil"
    assert_equal 3_304, item.calculated_amount
    item.tax_basis = "inclusive"
    assert_equal 3_003, item.calculated_amount
    manual = @wedding.budget_items.new(direction: "expense", category: "other", title: "架空直接税込", amount_yen: 1_234,
      certainty: "estimate", tax_basis: "exclusive")
    assert manual.valid?
    item.tax_basis = "exclusive"
    item.tax_rate = nil
    refute item.valid?
    item.tax_rate = 101
    refute item.valid?
  end

  test "travel source kinds distinguish guest and household" do
    household = @wedding.households.create!(code: "H-TRAVEL", name: "架空交通家")
    guest = household.guests.create!(name: "架空交通 太郎")
    household_item = @wedding.budget_items.create!(direction: "expense", category: "travel", title: "世帯お車代", amount_yen: 5_000,
      source_kind: "travel_household", source_id: household.id)
    guest_item = @wedding.budget_items.create!(direction: "expense", category: "travel", title: "個人お車代", amount_yen: 3_000,
      source_kind: "travel_guest", source_id: guest.id)
    assert_equal household.id, household_item.source_id
    assert_equal guest.id, guest_item.source_id
    refute @wedding.budget_items.new(direction: "expense", category: "travel", title: "曖昧お車代", amount_yen: 1_000,
      source_kind: "travel", source_id: household.id).valid?
  end

  test "guest gender invitation status and multiple roles are validated" do
    guest = @wedding.guests.create!(name: "架空属性 太郎", gender: "male", invitation_status: "invited", roles: %w[reception speech])
    assert_equal %w[reception speech], guest.roles
    guest.roles = ["unsupported"]
    refute guest.valid?
  end

  test "guest attendance changes quantity estimates while confirmed amounts stay fixed" do
    household = @wedding.households.create!(code: "H-RECALC", name: "架空再計算家")
    table = @wedding.seating_tables.create!(label: "再計算卓")
    estimates = {
      "attending_guests" => 100,
      "attending_adults" => 200,
      "attending_children" => 300,
      "attending_households" => 400,
      "seating_tables" => 500
    }.to_h do |quantity_basis, unit_price|
      [quantity_basis, @wedding.budget_items.create!(direction: "expense", category: "other", title: "架空出欠再計算", certainty: "estimate",
        calculation_mode: "quantity", quantity_basis: quantity_basis, unit_price: unit_price)]
    end
    confirmed = @wedding.budget_items.create!(direction: "expense", category: "other", title: "架空確定再計算", certainty: "confirmed",
      calculation_mode: "quantity", quantity_basis: "attending_guests", unit_price: 999, amount_yen: 9_999)
    guest = @wedding.guests.create!(name: "架空再計算 太郎", attendance: "pending", age_group: "adult")
    previous_lock_version = estimates.fetch("attending_guests").lock_version

    guest.update!(attendance: "attending", household_id: household.id, seating_table_id: table.id)
    assert_equal [100, 200, 0, 400, 500], estimates.transform_values(&:reload).values.map(&:amount_yen)
    assert_operator estimates.fetch("attending_guests").lock_version, :>, previous_lock_version
    assert_equal 9_999, confirmed.reload.amount_yen

    guest.update!(age_group: "child", household_id: nil, seating_table_id: nil)
    assert_equal [100, 0, 300, 0, 0], estimates.transform_values(&:reload).values.map(&:amount_yen)
    assert_equal 9_999, confirmed.reload.amount_yen

    guest.destroy!
    assert_equal [0, 0, 0, 0, 0], estimates.transform_values(&:reload).values.map(&:amount_yen)
    assert_equal 9_999, confirmed.reload.amount_yen
  end

  test "cash gift rule changes recalculate estimates but preserve confirmed gifts" do
    rule = @wedding.cash_gift_rules.create!(label: "架空再計算区分", default_amount_yen: 100_000)
    estimate_household = @wedding.households.create!(code: "H-CASH-EST", name: "架空概算家", cash_gift_rule: rule)
    confirmed_household = @wedding.households.create!(code: "H-CASH-CONF", name: "架空確定家", cash_gift_rule: rule)
    estimate_household.ensure_cash_gift_budget_item!
    confirmed_household.ensure_cash_gift_budget_item!.update!(certainty: "confirmed", amount_yen: 111_000)

    rule.update!(default_amount_yen: 120_000)
    assert_equal 120_000, estimate_household.cash_gift_budget_item.reload.amount_yen
    assert_equal 111_000, confirmed_household.cash_gift_budget_item.reload.amount_yen
    rule.destroy!
    assert estimate_household.cash_gift_budget_item.reload.persisted?
    assert confirmed_household.cash_gift_budget_item.reload.persisted?
  end

  test "gift set changes recalculate all linked estimate assignments only" do
    set = @wedding.gift_sets.create!(name: "架空再計算引出物")
    set.gift_set_items.create!(kind: "gift", name: "架空再計算品", unit_price_yen: 5_000, tax_basis: "inclusive")
    households = 3.times.map { |i| @wedding.households.create!(code: "H-GIFT-#{i}", name: "架空引出物家#{i}") }
    assignments = households.map { |household| @wedding.gift_assignments.create!(household: household, gift_set: set, quantity: 1) }
    estimate_items = assignments.first(2).map do |assignment|
      @wedding.budget_items.create!(direction: "expense", category: "gift", title: "架空引出物再計算", amount_yen: 5_000,
        certainty: "estimate", source_kind: "gift_assignment", source_id: assignment.id)
    end
    confirmed_item = @wedding.budget_items.create!(direction: "expense", category: "gift", title: "架空引出物確定", amount_yen: 5_000,
      certainty: "confirmed", source_kind: "gift_assignment", source_id: assignments.last.id)

    set.gift_set_items.first.update!(unit_price_yen: 6_000)
    assert_equal [6_000, 6_000], estimate_items.map { |item| item.reload.amount_yen }
    assert_equal 5_000, confirmed_item.reload.amount_yen
  end

  test "individual gift assignment creates one linked budget item and can coexist with household assignment" do
    household = @wedding.households.create!(code: "H-IND-GIFT", name: "架空個人引出物家")
    guest = household.guests.create!(name: "架空個別 太郎", attendance: "attending")
    household_set = @wedding.gift_sets.create!(name: "架空世帯セット")
    household_set.gift_set_items.create!(kind: "gift", name: "架空世帯品", unit_price_yen: 5_000)
    individual_set = @wedding.gift_sets.create!(name: "架空個人セット")
    individual_set.gift_set_items.create!(kind: "gift", name: "架空個人品", unit_price_yen: 3_000)
    @wedding.gift_assignments.create!(household: household, gift_set: household_set, quantity: 1)

    post guest_gift_assignments_path, params: { guest_gift_assignment: { guest_id: guest.id, gift_set_id: individual_set.id, quantity: 1, included: true } }
    assert_redirected_to guests_path(tab: "gifts")
    assignment = @wedding.guest_gift_assignments.find_by!(guest: guest)
    assert_equal 3_000, assignment.budget_item.reload.amount_yen
    assert_equal "guest_gift_assignment", assignment.budget_item.source_kind
    assert_equal 1, @wedding.budget_items.where(source_kind: "guest_gift_assignment", source_id: assignment.id).count
  end

  test "individual gift estimate recalculates while confirmed amount stays fixed" do
    guest = @wedding.guests.create!(name: "架空個人再計算")
    set = @wedding.gift_sets.create!(name: "架空個人再計算セット")
    item = set.gift_set_items.create!(kind: "gift", name: "架空品", unit_price_yen: 4_000)
    assignment = @wedding.guest_gift_assignments.create!(guest: guest, gift_set: set)
    budget = @wedding.budget_items.create!(direction: "expense", category: "gift", title: "架空個人再計算費", amount_yen: 4_000,
      certainty: "estimate", source_kind: "guest_gift_assignment", source_id: assignment.id)
    assignment.update!(budget_item: budget)

    item.update!(unit_price_yen: 4_500)
    assert_equal 4_500, budget.reload.amount_yen
    budget.update!(certainty: "confirmed", amount_yen: 5_000)
    item.update!(unit_price_yen: 6_000)
    assert_equal 5_000, budget.reload.amount_yen
  end
end
