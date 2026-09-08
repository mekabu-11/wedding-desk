class GiftAssignmentsController < ApplicationController
  before_action :set_assignment, only: %i[edit update destroy]

  def new
    @gift_assignment = current_wedding.gift_assignments.new(quantity: 1, included: true)
    load_options
  end

  def create
    @gift_assignment = current_wedding.gift_assignments.new(assignment_params)
    GiftAssignment.transaction do
      @gift_assignment.save!
      create_or_update_budget_item!
    end
    redirect_to guests_path(tab: "gifts"), notice: "引き出物を割り当てました。", status: :see_other
  rescue ActiveRecord::RecordInvalid
    load_options
    render :new, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    @gift_assignment.errors.add(:household_id, "この世帯には既に引き出物が割り当てられています")
    load_options
    render :new, status: :unprocessable_entity
  end

  def edit
    load_options
  end

  def update
    GiftAssignment.transaction do
      @gift_assignment.update!(assignment_params)
      create_or_update_budget_item!
    end
    redirect_to guests_path(tab: "gifts"), notice: "引き出物の割当を保存しました。", status: :see_other
  rescue ActiveRecord::RecordInvalid
    load_options
    render :edit, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    @gift_assignment.errors.add(:household_id, "この世帯には既に引き出物が割り当てられています")
    load_options
    render :edit, status: :unprocessable_entity
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_gift_assignment_path(@gift_assignment), alert: "別の操作で更新されています。最新の内容を確認してください。"
  end

  def destroy
    GiftAssignment.transaction do
      @gift_assignment.destroy!
    end
    redirect_to guests_path(tab: "gifts"), notice: "引き出物の割当を解除しました。明細は履歴のため除外で残ります。", status: :see_other
  rescue ActiveRecord::DeleteRestrictionError
    redirect_to guests_path(tab: "gifts"), alert: "この割当は削除できません。"
  end

  private

  def set_assignment
    @gift_assignment = current_wedding.gift_assignments.find(params[:id])
  end

  def assignment_params
    params.require(:gift_assignment).permit(:household_id, :gift_set_id, :quantity, :included, :notes, :lock_version)
  end

  def load_options
    @households = current_wedding.households.active.order(:id)
    @gift_sets = current_wedding.gift_sets.includes(:gift_set_items).order(:id)
  end

  def create_or_update_budget_item!
    GiftAssignmentBudgetItemSync.call!(@gift_assignment)
  end
end
