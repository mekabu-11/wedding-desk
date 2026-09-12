class CashGiftRulesController < ApplicationController
  before_action :set_rule, only: %i[edit update destroy]

  def new
    @cash_gift_rule = current_wedding.cash_gift_rules.new
  end

  def create
    @cash_gift_rule = current_wedding.cash_gift_rules.new(rule_params)
    saved = ActiveRecord::Base.transaction do
      result = @cash_gift_rule.save
      record_change!(@cash_gift_rule, "cash_gift_rule_created", after: change_snapshot(@cash_gift_rule, :label, :default_amount_yen, :fallback_attribute, :fallback_value)) if result
      result
    end
    if saved
      redirect_to guests_path(tab: "households"), notice: "ご祝儀区分を追加しました。", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    before = change_snapshot(@cash_gift_rule, :label, :default_amount_yen, :fallback_attribute, :fallback_value)
    saved = ActiveRecord::Base.transaction do
      result = @cash_gift_rule.update(rule_params)
      after = change_snapshot(@cash_gift_rule, :label, :default_amount_yen, :fallback_attribute, :fallback_value)
      record_change!(@cash_gift_rule, "cash_gift_rule_updated", before: before, after: after) if result && before != after
      result
    end
    if saved
      redirect_to guests_path(tab: "households"), notice: "ご祝儀区分を保存しました。既存の確定明細は変更していません。", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_cash_gift_rule_path(@cash_gift_rule), alert: "別の操作で更新されています。最新の内容を確認してください。"
  end

  def destroy
    before = change_snapshot(@cash_gift_rule, :label, :default_amount_yen, :fallback_attribute, :fallback_value)
    ActiveRecord::Base.transaction do
      @cash_gift_rule.destroy!
      record_change!(@cash_gift_rule, "cash_gift_rule_deleted", before: before)
    end
    redirect_to guests_path(tab: "households"), notice: "ご祝儀区分を削除しました。", status: :see_other
  end

  private

  def set_rule
    @cash_gift_rule = current_wedding.cash_gift_rules.find(params[:id])
  end

  def rule_params
    params.require(:cash_gift_rule).permit(:label, :default_amount_yen, :fallback_attribute, :fallback_value, :lock_version)
  end
end
