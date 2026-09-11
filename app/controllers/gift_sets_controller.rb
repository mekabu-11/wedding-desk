class GiftSetsController < ApplicationController
  before_action :set_gift_set, only: %i[edit update destroy]

  def new
    @gift_set = current_wedding.gift_sets.new
    3.times { @gift_set.gift_set_items.build }
  end

  def create
    @gift_set = current_wedding.gift_sets.new(gift_set_params)
    saved = ActiveRecord::Base.transaction do
      result = @gift_set.save
      record_change!(@gift_set, "gift_set_created", after: change_snapshot(@gift_set, :name, :notes)) if result
      result
    end
    if saved
      redirect_to guests_path(tab: "gifts"), notice: "引き出物セットを追加しました。", status: :see_other
    else
      3.times { @gift_set.gift_set_items.build } if @gift_set.gift_set_items.empty?
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    3.times { @gift_set.gift_set_items.build }
  end

  def update
    before = change_snapshot(@gift_set, :name, :notes)
    saved = ActiveRecord::Base.transaction do
      result = @gift_set.update(gift_set_params)
      after = change_snapshot(@gift_set, :name, :notes)
      record_change!(@gift_set, "gift_set_updated", before: before, after: after) if result && before != after
      result
    end
    if saved
      redirect_to guests_path(tab: "gifts"), notice: "引き出物セットを保存しました。", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_gift_set_path(@gift_set), alert: "別の操作で更新されています。最新の内容を確認してください。"
  end

  def destroy
    before = change_snapshot(@gift_set, :name, :notes)
    ActiveRecord::Base.transaction do
      @gift_set.destroy!
      record_change!(@gift_set, "gift_set_deleted", before: before)
    end
    redirect_to guests_path(tab: "gifts"), notice: "引き出物セットを削除しました。", status: :see_other
  rescue ActiveRecord::DeleteRestrictionError
    redirect_to guests_path(tab: "gifts"), alert: "割当があるセットは削除できません。先に割当を見直してください。"
  end

  private

  def set_gift_set
    @gift_set = current_wedding.gift_sets.find(params[:id])
  end

  def gift_set_params
    params.require(:gift_set).permit(:name, :notes, :lock_version,
      gift_set_items_attributes: [:id, :kind, :name, :unit_price_yen, :tax_basis, :tax_rate, :rounding, :_destroy, :lock_version])
  end
end
