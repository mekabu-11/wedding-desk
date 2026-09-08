class ChangeSetsController < ApplicationController
  before_action :set_change_set

  def show
    @document = @change_set.document
    @operations = @change_set.change_operations.order(:id)
  end

  def apply
    ids = Array(params[:operation_ids]).reject(&:blank?)
    ChangeSet::Apply.call(change_set: @change_set, operation_ids: ids)
    redirect_to document_path(@change_set.document), notice: "選択した変更を反映しました。", status: :see_other
  rescue ChangeSet::Apply::Conflict
    redirect_to change_set_path(@change_set), alert: "競合があるため反映していません。内容を再確認してください。"
  rescue ChangeSet::Apply::InvalidOperation, ChangeSet::Apply::InvalidEvidence => error
    redirect_to change_set_path(@change_set), alert: error.message
  end

  private

  def set_change_set
    @change_set = current_wedding.change_sets.find(params[:id])
  end
end
