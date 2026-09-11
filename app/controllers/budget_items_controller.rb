class BudgetItemsController < ApplicationController
  before_action :set_budget_item, only: %i[edit update destroy]

  def index
    @direction = params[:direction].presence_in(BudgetItem::DIRECTIONS.keys)
    @certainty = params[:certainty].presence_in(BudgetItem::CERTAINTIES.keys)
    @payment_status_filter = params[:payment_status].presence_in(BudgetItem::PAYMENT_STATUS_FILTERS.keys)
    scope = current_wedding.budget_items.includes(:money_movements, :gift_assignment).order(:id)
    scope = scope.where(direction: @direction) if @direction
    scope = scope.where(certainty: @certainty) if @certainty
    @page = [params[:page].to_i, 1].max
    if @payment_status_filter
      filtered = scope.to_a.select { |item| item.payment_status_key == @payment_status_filter }
      @total_count = filtered.size
      @budget_items = filtered.slice((@page - 1) * 30, 30) || []
    else
      @total_count = scope.count
      @budget_items = scope.offset((@page - 1) * 30).limit(30)
    end
    @expense_total = current_wedding.budget_items.included.expenses.sum(:amount_yen)
    @income_total = current_wedding.budget_items.included.income.sum(:amount_yen)
    @unknown_count = current_wedding.budget_items.included.where(amount_yen: nil).count
    @burden_estimate = (@expense_total || 0) - (@income_total || 0)
  end

  def new
    @budget_item = current_wedding.budget_items.new(direction: "expense", certainty: "estimate", inclusion: "included", category: "other")
  end

  def create
    @budget_item = current_wedding.budget_items.new(budget_item_params.merge(source_kind: "manual", source_id: nil))
    saved = ActiveRecord::Base.transaction do
      result = @budget_item.save
      record_change!(@budget_item, "budget_item_created", after: budget_change_snapshot(@budget_item)) if result
      result
    end
    if saved
      redirect_to budget_items_path, notice: "金額を追加しました。", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @change_events = ChangeEvent.for_target(@budget_item).where(wedding_id: current_wedding.id).limit(10)
  end

  def update
    before = budget_change_snapshot(@budget_item)
    saved = ActiveRecord::Base.transaction do
      result = @budget_item.update(budget_item_params)
      after = budget_change_snapshot(@budget_item)
      record_change!(@budget_item, "budget_item_updated", before: before, after: after) if result && before != after
      result
    end
    if saved
      redirect_to budget_items_path, notice: "金額を保存しました。支払い状況は履歴から表示しています。", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_budget_item_path(@budget_item), alert: "別の操作で更新されています。最新の内容を確認してください。"
  end

  def destroy
    if @budget_item.money_movements.exists?
      return redirect_to budget_items_path, alert: "入出金履歴がある明細は削除できません。除外または訂正してください。"
    end
    before = budget_change_snapshot(@budget_item)
    ActiveRecord::Base.transaction do
      @budget_item.destroy!
      record_change!(@budget_item, "budget_item_deleted", before: before)
    end
    redirect_to budget_items_path, notice: "金額を削除しました。", status: :see_other
  end

  private

  def set_budget_item
    @budget_item = current_wedding.budget_items.find(params[:id])
  end

  def budget_item_params
    params.require(:budget_item).permit(:direction, :category, :title, :amount_yen, :certainty, :inclusion,
      :calculation_mode, :quantity_basis, :unit_price, :manual_quantity, :tax_basis, :tax_rate, :rounding, :lock_version)
  end

  def budget_change_snapshot(item)
    change_snapshot(item, :direction, :category, :title, :amount_yen, :certainty, :inclusion,
      :calculation_mode, :quantity_basis, :unit_price, :manual_quantity, :tax_basis, :tax_rate,
      :rounding, :source_kind, :source_id)
  end
end
