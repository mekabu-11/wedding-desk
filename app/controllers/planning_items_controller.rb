class PlanningItemsController < ApplicationController
  before_action :set_planning_item, only: %i[show edit update destroy]

  def index
    @category = params[:category].presence_in(PlanningItem::CATEGORIES.keys)
    scope = current_wedding.planning_items.includes(planning_options: :music_detail).order(:position, :id)
    scope = scope.where(category: @category) if @category
    @page = [params[:page].to_i, 1].max
    @total_count = scope.count
    @planning_items = scope.offset((@page - 1) * 30).limit(30)
  end

  def show
    @planning_options = @planning_item.planning_options.includes(:music_detail).order(:id).to_a
    @planning_options = @planning_options.sort_by { |option| [option.music_detail&.scene.to_s, option.id] } if @planning_item.category == "music"
    @new_option = @planning_item.planning_options.new(status: "draft")
    @budget_items = current_wedding.budget_items.order(:id).limit(200)
    @tasks = current_wedding.tasks.open_items.order(:id).limit(200)
    @budget_item_options = @budget_items.map { |budget_item| ["#{budget_item.title}（#{budget_item.amount_yen || '未確認'}円）", budget_item.id] }
    @task_options = @tasks.map { |task| [task.title, task.id] }
    @cost_mode_options = [["既存BudgetItemへ紐付け", "existing"], ["新しい支出を追加", "new"], ["追加費用なし", "none"], ["金額未確認で追加", "unknown"]]
    @cost_links = @planning_item.planning_cost_links.includes(:budget_item).order(:id)
    @task_links = @planning_item.task_planning_links.includes(:task).order(:id)
    history = current_wedding.change_events.where(target_type: "PlanningItem", target_id: @planning_item.id)
    option_ids = @planning_options.map(&:id)
    if option_ids.any?
      history = history.or(current_wedding.change_events.where(target_type: "PlanningOption", target_id: option_ids))
    end
    @change_events = history.order(created_at: :desc).limit(10)
  end

  def new
    @planning_item = current_wedding.planning_items.new(category: "other")
  end

  def create
    @planning_item = current_wedding.planning_items.new(planning_item_params)
    if @planning_item.save
      redirect_to planning_item_path(@planning_item), notice: "検討項目を追加しました。", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @planning_item.update(planning_item_params)
      redirect_to planning_item_path(@planning_item), notice: "検討項目を保存しました。", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_planning_item_path(@planning_item), alert: "別の操作で更新されています。最新の内容を確認してください。"
  end

  def destroy
    @planning_item.destroy!
    redirect_to planning_items_path, notice: "検討項目を削除しました。", status: :see_other
  end

  private

  def set_planning_item
    @planning_item = current_wedding.planning_items.find(params[:id])
  end

  def planning_item_params
    params.require(:planning_item).permit(:title, :category, :notes, :position, :lock_version)
  end
end
