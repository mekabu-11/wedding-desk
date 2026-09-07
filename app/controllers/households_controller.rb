class HouseholdsController < ApplicationController
  before_action :set_household, only: %i[edit update destroy]

  def new
    @household = current_wedding.households.new
    load_options
  end

  def create
    @household = current_wedding.households.new(household_params)
    Household.transaction do
      @household.save!
      ensure_cash_gift if params[:cash_gift] == "1"
    end
    redirect_to guests_path(tab: "households"), notice: "世帯を追加しました。", status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    load_options
    @household.errors.add(:base, "ご祝儀明細を保存できませんでした") if error.record.is_a?(BudgetItem)
    render :new, status: :unprocessable_entity
  end

  def edit
    load_options
  end

  def update
    Household.transaction do
      @household.update!(household_params)
      ensure_cash_gift if params[:cash_gift] == "1"
    end
    redirect_to guests_path(tab: "households"), notice: "世帯を保存しました。", status: :see_other
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_household_path(@household), alert: "別の操作で更新されています。最新の内容を確認してください。"
  rescue ActiveRecord::RecordInvalid => error
    load_options
    @household.errors.add(:base, "ご祝儀明細を保存できませんでした") if error.record.is_a?(BudgetItem)
    render :edit, status: :unprocessable_entity
  end

  def destroy
    if @household.cash_gift_budget_item.present?
      return redirect_to guests_path(tab: "households"), alert: "ご祝儀明細がある世帯は削除できません。アーカイブしてください。"
    end
    @household.destroy!
    redirect_to guests_path(tab: "households"), notice: "世帯を削除しました。", status: :see_other
  rescue ActiveRecord::DeleteRestrictionError
    redirect_to guests_path(tab: "households"), alert: "引き出物割当がある世帯は削除できません。アーカイブしてください。"
  rescue ActiveRecord::RecordNotDestroyed
    redirect_to guests_path(tab: "households"), alert: "ご祝儀明細がある世帯は削除できません。アーカイブしてください。"
  end

  private

  def set_household
    @household = current_wedding.households.find(params[:id])
  end

  def household_params
    params.require(:household).permit(:code, :name, :cash_gift_rule_id, :notes, :archived, :lock_version)
  end

  def load_options
    @cash_gift_rules = current_wedding.cash_gift_rules.order(:id)
  end

  def ensure_cash_gift
    @household.ensure_cash_gift_budget_item!
  end
end
