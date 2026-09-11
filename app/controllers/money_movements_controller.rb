class MoneyMovementsController < ApplicationController
  before_action :set_budget_item
  before_action :set_movement, only: %i[edit update destroy]

  def new
    @money_movement = @budget_item.money_movements.new(occurred_on: Date.current)
  end

  def create
    if (existing = existing_idempotent_movement)
      return redirect_to budget_items_path, notice: "同じ入出金履歴は登録済みです。", status: :see_other if same_idempotent_movement?(existing)

      return render_idempotency_conflict
    end
    @money_movement = @budget_item.money_movements.new(movement_params.merge(wedding: current_wedding))
    saved = ActiveRecord::Base.transaction do
      result = @money_movement.save
      record_change!(@money_movement, "money_movement_created", after: movement_change_snapshot(@money_movement)) if result
      result
    end
    if saved
      redirect_to budget_items_path, notice: "入出金履歴を追加しました。", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    existing = existing_idempotent_movement
    if existing && same_idempotent_movement?(existing)
      redirect_to budget_items_path, notice: "同じ入出金履歴は登録済みです。", status: :see_other
    elsif existing
      render_idempotency_conflict
    else
      raise
    end
  end

  def edit; end

  def update
    before = movement_change_snapshot(@money_movement)
    saved = ActiveRecord::Base.transaction do
      result = @money_movement.update(movement_params)
      after = movement_change_snapshot(@money_movement)
      record_change!(@money_movement, "money_movement_updated", before: before, after: after) if result && before != after
      result
    end
    if saved
      redirect_to budget_items_path, notice: "入出金履歴を保存しました。", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_budget_item_money_movement_path(@budget_item, @money_movement), alert: "別の操作で更新されています。最新の内容を確認してください。"
  end

  def destroy
    before = movement_change_snapshot(@money_movement)
    ActiveRecord::Base.transaction do
      @money_movement.destroy!
      record_change!(@money_movement, "money_movement_deleted", before: before)
    end
    redirect_to budget_items_path, notice: "入出金履歴を削除しました。", status: :see_other
  end

  private

  def set_budget_item
    @budget_item = current_wedding.budget_items.find(params[:budget_item_id])
  end

  def set_movement
    @money_movement = @budget_item.money_movements.find(params[:id])
  end

  def movement_params
    params.require(:money_movement).permit(:occurred_on, :kind, :amount_yen, :note, :idempotency_key, :lock_version)
  end

  def same_idempotent_movement?(existing)
    existing.budget_item_id == @budget_item.id &&
      existing.occurred_on.to_s == movement_params[:occurred_on].to_s &&
      existing.kind == movement_params[:kind].to_s &&
      existing.amount_yen == movement_params[:amount_yen].to_i
  end

  def existing_idempotent_movement
    key = movement_params[:idempotency_key].presence
    key && current_wedding.money_movements.find_by(idempotency_key: key)
  end

  def render_idempotency_conflict
    @money_movement = @budget_item.money_movements.new(movement_params)
    @money_movement.errors.add(:idempotency_key, "同じ識別子で異なる入出金内容は登録できません")
    render :new, status: :unprocessable_entity
  end

  def movement_change_snapshot(movement)
    change_snapshot(movement, :budget_item_id, :occurred_on, :kind, :amount_yen, :note, :idempotency_key)
  end
end
