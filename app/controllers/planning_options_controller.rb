class PlanningOptionsController < ApplicationController
  before_action :set_planning_item_from_nested, only: :create
  before_action :set_option, only: %i[edit update destroy select reject]

  def create
    @option = @planning_item.planning_options.new(option_params.merge(wedding: current_wedding))
    saved = ActiveRecord::Base.transaction do
      result = @option.save
      record_change!(@option, "planning_option_created", after: option_change_snapshot(@option)) if result
      result
    end
    if saved
      redirect_to planning_item_path(@planning_item), notice: "候補を追加しました。", status: :see_other
    else
      redirect_to planning_item_path(@planning_item), alert: "候補を保存できませんでした。タイトルを確認してください.", status: :see_other
    end
  end

  def edit; end

  def update
    before = option_change_snapshot(@option)
    saved = ActiveRecord::Base.transaction do
      result = @option.update(option_params)
      after = option_change_snapshot(@option)
      record_change!(@option, "planning_option_updated", before: before, after: after) if result && before != after
      result
    end
    if saved
      redirect_to planning_item_path(@option.planning_item), notice: "候補を保存しました。", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_planning_option_path(@option), alert: "別の操作で更新されています。最新の内容を確認してください。"
  end

  def select
    cost_mode = params[:cost_mode].presence
    unless %w[existing new none unknown].include?(cost_mode)
      return redirect_to planning_item_path(@option.planning_item), alert: "採用時の費用処理を選択してください。"
    end
    PlanningOption.transaction do
      @option.planning_item.with_lock do
        previous = @option.planning_item.planning_options.where(status: "selected").where.not(id: @option.id).first
        @option.planning_item.planning_cost_links.delete_all
        @option.planning_item.planning_options.where.not(id: @option.id).where(status: "selected").update_all(status: "rejected", updated_at: Time.current)
        @option.update!(status: "selected")
        create_cost_link!(cost_mode)
        ChangeEvent.record!(wedding: current_wedding, target: @option, action: "planning_option_selected",
          before: { selected_option_id: previous&.id }.to_json, after: { selected_option_id: @option.id, cost_mode: cost_mode }.to_json,
          source: "manual", actor: current_user)
      end
    end
    redirect_to planning_item_path(@option.planning_item), notice: "候補を採用しました。", status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActionController::ParameterMissing
    redirect_to planning_item_path(@option.planning_item), alert: "採用と費用の紐付けを保存できませんでした。入力を確認してください。", status: :see_other
  end

  def reject
    before = @option.status
    @option.update!(status: "rejected")
    ChangeEvent.record!(wedding: current_wedding, target: @option, action: "planning_option_rejected",
      before: { status: before }.to_json, after: { status: "rejected" }.to_json, source: "manual", actor: current_user) if before != "rejected"
    redirect_to planning_item_path(@option.planning_item), notice: "候補を見送りました。", status: :see_other
  end

  def destroy
    before = option_change_snapshot(@option)
    ActiveRecord::Base.transaction do
      @option.destroy!
      record_change!(@option, "planning_option_deleted", before: before)
    end
    redirect_to planning_item_path(@option.planning_item), notice: "候補を削除しました。", status: :see_other
  end

  private

  def set_planning_item_from_nested
    @planning_item = current_wedding.planning_items.find(params[:planning_item_id])
  end

  def set_option
    @option = current_wedding.planning_options.find(params[:id])
  end

  def option_params
    permitted = params.require(:planning_option).permit(:title, :description, :reference_price_yen, :status, :lock_version)
    requested_status = permitted[:status].to_s
    if action_name == "create"
      permitted[:status] = requested_status.presence_in(%w[draft considering rejected]) || "draft"
    elsif @option&.selected?
      permitted.delete(:status)
    elsif requested_status.present? && !%w[draft considering rejected].include?(requested_status)
      permitted.delete(:status)
    end
    permitted
  end

  def option_change_snapshot(option)
    change_snapshot(option, :title, :description, :status, :reference_price_yen)
  end

  def create_cost_link!(cost_mode)
    return if cost_mode == "none"

    budget_item = case cost_mode
    when "existing"
      current_wedding.budget_items.find(params.require(:budget_item_id))
    when "new", "unknown"
      current_wedding.budget_items.create!(direction: "expense", category: @option.planning_item.category,
        title: @option.title, amount_yen: cost_mode == "unknown" ? nil : @option.reference_price_yen,
        certainty: "estimate", inclusion: "included", calculation_mode: "manual", source_kind: "manual")
    end
    current_wedding.planning_cost_links.create!(planning_item: @option.planning_item, budget_item: budget_item)
  end
end
