class GuestGiftAssignmentsController < ApplicationController
  before_action :set_assignment, only: %i[edit update destroy]

  def new
    @guest_gift_assignment = current_wedding.guest_gift_assignments.new(quantity: 1, included: true)
    load_options
  end

  def create
    @guest_gift_assignment = current_wedding.guest_gift_assignments.new(assignment_params)
    GuestGiftAssignment.transaction do
      @guest_gift_assignment.save!
      create_or_update_budget_item!
      record_change!(@guest_gift_assignment, "guest_gift_assignment_created", after: change_snapshot(@guest_gift_assignment, :guest_id, :gift_set_id, :quantity, :included, :notes))
    end
    redirect_to guests_path(tab: "gifts"), notice: "個人の引き出物を割り当てました。", status: :see_other
  rescue ActiveRecord::RecordInvalid
    load_options
    render :new, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    @guest_gift_assignment.errors.add(:guest_id, "このゲストには既に個人引き出物の割当があります")
    load_options
    render :new, status: :unprocessable_entity
  end

  def edit
    load_options
  end

  def update
    GuestGiftAssignment.transaction do
      before = change_snapshot(@guest_gift_assignment, :guest_id, :gift_set_id, :quantity, :included, :notes)
      @guest_gift_assignment.update!(assignment_params)
      create_or_update_budget_item!
      after = change_snapshot(@guest_gift_assignment, :guest_id, :gift_set_id, :quantity, :included, :notes)
      record_change!(@guest_gift_assignment, "guest_gift_assignment_updated", before: before, after: after) if before != after
    end
    redirect_to guests_path(tab: "gifts"), notice: "個人の引き出物を保存しました。", status: :see_other
  rescue ActiveRecord::RecordInvalid
    load_options
    render :edit, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    @guest_gift_assignment.errors.add(:guest_id, "このゲストには既に個人引き出物の割当があります")
    load_options
    render :edit, status: :unprocessable_entity
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_guest_gift_assignment_path(@guest_gift_assignment), alert: "別の操作で更新されています。最新の内容を確認してください。"
  end

  def destroy
    before = change_snapshot(@guest_gift_assignment, :guest_id, :gift_set_id, :quantity, :included, :notes)
    GuestGiftAssignment.transaction do
      @guest_gift_assignment.destroy!
      record_change!(@guest_gift_assignment, "guest_gift_assignment_deleted", before: before)
    end
    redirect_to guests_path(tab: "gifts"), notice: "個人の引き出物を解除しました。明細は履歴のため除外で残ります。", status: :see_other
  rescue ActiveRecord::DeleteRestrictionError
    redirect_to guests_path(tab: "gifts"), alert: "この割当は削除できません。"
  end

  private

  def set_assignment
    @guest_gift_assignment = current_wedding.guest_gift_assignments.find(params[:id])
  end

  def assignment_params
    params.require(:guest_gift_assignment).permit(:guest_id, :gift_set_id, :quantity, :included, :notes, :lock_version)
  end

  def load_options
    @guests = current_wedding.guests.includes(:household).ordered
    @gift_sets = current_wedding.gift_sets.includes(:gift_set_items).order(:id)
  end

  def create_or_update_budget_item!
    GuestGiftAssignmentBudgetItemSync.call!(@guest_gift_assignment)
  end
end
