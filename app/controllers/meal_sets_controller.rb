class MealSetsController < ApplicationController
  before_action :set_meal_set, only: %i[edit update destroy]

  def new
    @meal_set = current_wedding.meal_sets.new(target_age_group: "adult", default_for_target: true)
  end

  def create
    @meal_set = current_wedding.meal_sets.new(meal_set_params)
    MealSet.transaction do
      clear_existing_default!
      @meal_set.save!
      record_change!(@meal_set, "meal_set_created", after: change_snapshot(@meal_set, :name, :target_age_group, :unit_price_yen, :default_for_target, :notes))
    end
    redirect_to guests_path(tab: "meals"), notice: "食事セットを追加しました。", status: :see_other
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    @meal_set.errors.add(:default_for_target, "同じ対象の標準セットは1つだけ設定できます")
    render :new, status: :unprocessable_entity
  end

  def edit; end

  def update
    before = change_snapshot(@meal_set, :name, :target_age_group, :unit_price_yen, :default_for_target, :notes)
    MealSet.transaction do
      clear_existing_default!
      @meal_set.update!(meal_set_params)
      after = change_snapshot(@meal_set, :name, :target_age_group, :unit_price_yen, :default_for_target, :notes)
      record_change!(@meal_set, "meal_set_updated", before: before, after: after) if before != after
    end
    redirect_to guests_path(tab: "meals"), notice: "食事セットを保存しました。", status: :see_other
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    @meal_set.errors.add(:default_for_target, "同じ対象の標準セットは1つだけ設定できます")
    render :edit, status: :unprocessable_entity
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_meal_set_path(@meal_set), alert: "別の操作で更新されています。最新の内容を確認してください。"
  end

  def destroy
    before = change_snapshot(@meal_set, :name, :target_age_group, :unit_price_yen, :default_for_target, :notes)
    MealSet.transaction do
      @meal_set.destroy!
      record_change!(@meal_set, "meal_set_deleted", before: before)
    end
    redirect_to guests_path(tab: "meals"), notice: "食事セットを削除しました。関連する概算費用は履歴として除外されます。", status: :see_other
  rescue ActiveRecord::RecordNotDestroyed
    redirect_to guests_path(tab: "meals"), alert: "食事セットを削除できませんでした。"
  end

  private

  def set_meal_set
    @meal_set = current_wedding.meal_sets.find(params[:id])
  end

  def meal_set_params
    params.require(:meal_set).permit(:name, :target_age_group, :unit_price_yen, :default_for_target, :notes, :lock_version)
  end

  def clear_existing_default!
    return unless ActiveModel::Type::Boolean.new.cast(meal_set_params[:default_for_target])

    target = meal_set_params[:target_age_group].presence || @meal_set.target_age_group
    current_wedding.meal_sets.where(target_age_group: target, default_for_target: true).where.not(id: @meal_set.id).update_all(default_for_target: false)
  end
end
