class BudgetItemsController < ApplicationController
  before_action :set_budget_item, only: %i[edit update destroy]

  def index
    @direction = params[:direction].presence_in(BudgetItem::DIRECTIONS.keys)
    @budget_items = current_wedding.budget_items.includes(:money_movements, :gift_assignment).order(:id)
    @budget_items = @budget_items.where(direction: @direction) if @direction
    @page = [params[:page].to_i, 1].max
    @total_count = @budget_items.count
    @budget_items = @budget_items.offset((@page - 1) * 30).limit(30)
    @expense_total = current_wedding.budget_items.included.expenses.sum(:amount_yen)
    @income_total = current_wedding.budget_items.included.income.sum(:amount_yen)
    @unknown_count = current_wedding.budget_items.included.where(amount_yen: nil).count
  end

  def new
    @budget_item = current_wedding.budget_items.new(direction: "expense", certainty: "estimate", inclusion: "included", category: "other")
  end

  def create
    @budget_item = current_wedding.budget_items.new(budget_item_params.merge(source_kind: "manual", source_id: nil))
    if @budget_item.save
      redirect_to budget_items_path, notice: "金額を追加しました。", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @budget_item.update(budget_item_params)
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
    @budget_item.destroy!
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
end
