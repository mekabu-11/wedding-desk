class TasksController < ApplicationController
  before_action :set_task, only: %i[edit update]
  before_action :load_planning_context, only: %i[new create edit update]
  def index
    @assignee_options = Task.assignee_options(current_wedding)
    @status = params[:status].presence_in(Task::STATUSES.keys)
    @assignee = Task.normalize_assignee(params[:assignee]).presence_in(Task::ASSIGNEES.keys)
    @category = params[:category].presence_in(Task::CATEGORIES.keys)
    @period = params[:period].presence_in(%w[week overdue])
    @query = params[:q].to_s.strip.presence
    @view = params[:view].presence_in(%w[list gantt]) || "list"
    @range = params[:range].presence_in(%w[week month]) || "week"
    @anchor = Date.parse(params[:anchor].to_s) rescue Date.current
    scope = task_scope
    @matching_tasks, @search_limit_exceeded = search_tasks(scope, @query)
    @page = [params[:page].to_i, 1].max
    @total_count = @matching_tasks.is_a?(Array) ? @matching_tasks.size : @matching_tasks.count
    @tasks = @matching_tasks.is_a?(Array) ? (@matching_tasks.sort_by { |task| [task.due_on || task.due_at&.to_date || Date.new(9999, 12, 31), task.id] }.slice((@page - 1) * 30, 30) || []) : @matching_tasks.by_deadline.offset((@page - 1) * 30).limit(30).to_a
    if @view == "gantt"
      @range_start = if @range == "month"
        @anchor.beginning_of_month.beginning_of_week
      else
        @anchor.beginning_of_week
      end
      @range_end = if @range == "month"
        @anchor.end_of_month.end_of_week
      else
        @range_start + 6.days
      end
      range_tasks = @matching_tasks.is_a?(Array) ? @matching_tasks : @matching_tasks.order(:id).limit(2001).to_a
      @gantt_limit_exceeded = range_tasks.size > 2000
      range_tasks = Task.sort_for_gantt(range_tasks.first(2000))
      @gantt_tasks = Task.sort_for_gantt(range_tasks.select do |task|
        start_on = task.starts_on || task.due_on || task.due_at&.to_date
        end_on = task.due_on || task.due_at&.to_date || task.starts_on
        start_on && end_on && start_on <= @range_end && end_on >= @range_start
      end)
      @undated_tasks = Task.sort_for_gantt(range_tasks.select { |task| task.starts_on.blank? && task.due_on.blank? && task.due_at.blank? }).first(100)
    end
  end

  def bulk_preview
    load_filter_params
    ids = params[:selection] == "filtered" ? filtered_ids : params[:task_ids].to_a.map(&:to_i).uniq.first(2000)
    @tasks = current_wedding.tasks.where(id: ids).order(:id).to_a
    return redirect_to tasks_path, alert: "変更対象を選択してください。" if @tasks.empty?
    render :bulk_preview
  rescue TaskBulkUpdate::Invalid => error
    redirect_to tasks_path, alert: error.message
  end

  def bulk_update
    items = params[:items].respond_to?(:to_unsafe_h) ? params[:items].to_unsafe_h : {}
    TaskBulkUpdate.apply!(current_wedding, items, params.permit(:status, :assignee, :category).to_h, actor: current_user)
    redirect_to tasks_path, notice: "#{items.size}件のタスクを更新しました。", status: :see_other
  rescue TaskBulkUpdate::Invalid, ActiveRecord::StaleObjectError => error
    redirect_to tasks_path, alert: error.message.presence || "一括変更に失敗しました。全件変更していません。"
  end
  def edit; end
  def new
    @task = current_wedding.tasks.new(origin: "manual")
    @planning_item = planning_item_from_param
  end
  def create
    @task = current_wedding.tasks.new(task_params.merge(origin: "manual"))
    @planning_item = planning_item_from_param
    saved = ActiveRecord::Base.transaction do
      result = @task.save
      if result
        record_change!(@task, "task_created", after: change_snapshot(@task, :title, :description, :assignee, :starts_on, :due_on, :due_at, :status, :category))
        if @planning_item
          current_wedding.task_planning_links.create!(planning_item: @planning_item, task: @task)
          record_change!(@planning_item, "task_planning_link_created", after: { task_id: @task.id, task_title: @task.title })
        end
      end
      result
    end
    if saved
      redirect_to @planning_item ? planning_item_path(@planning_item) : tasks_path, notice: "タスクを追加しました。", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end
  def update
    before = change_snapshot(@task, :title, :description, :assignee, :starts_on, :due_on, :due_at, :status, :category)
    saved = ActiveRecord::Base.transaction do
      result = @task.update(task_params)
      after = change_snapshot(@task, :title, :description, :assignee, :starts_on, :due_on, :due_at, :status, :category)
      record_change!(@task, "task_updated", before: before, after: after) if result && before != after
      result
    end
    if saved
      redirect_to tasks_path, notice: "タスクを保存しました。", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_task_path(@task), alert: "別の操作で更新されています。最新の内容を確認して保存してください。"
  end
  private

  def task_scope
    scope = current_wedding.tasks.includes(candidate: :document)
    scope = @status ? scope.where(status: @status) : scope.open_items
    scope = scope.where(assignee: @assignee) if @assignee
    scope = scope.where(category: @category) if @category
    deadline = "COALESCE(due_on, (due_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Tokyo')::date)"
    if @period == "week"
      monday = Date.current.beginning_of_week
      scope = scope.where("(starts_on <= ? AND #{deadline} >= ?) OR (starts_on IS NULL AND #{deadline} BETWEEN ? AND ?)", monday + 6, monday, monday, monday + 6)
    elsif @period == "overdue"
      scope = scope.open_items.where("(due_on < ?) OR (due_at < ?)", Date.current, Time.current)
    end
    scope
  end

  def load_filter_params
    @status = params[:status].presence_in(Task::STATUSES.keys)
    @assignee = Task.normalize_assignee(params[:assignee]).presence_in(Task::ASSIGNEES.keys)
    @category = params[:category].presence_in(Task::CATEGORIES.keys)
    @period = params[:period].presence_in(%w[week overdue])
    @query = params[:q].to_s.strip.presence
  end

  def search_tasks(scope, query)
    return [scope, false] unless query
    rows = scope.limit(2001).to_a
    return [[], true] if rows.size > 2000

    normalized = query.downcase
    [rows.select { |task| [task.title, task.description].compact.any? { |value| value.to_s.downcase.include?(normalized) } }, false]
  end

  def filtered_ids
    result, overflow = search_tasks(task_scope, @query)
    raise TaskBulkUpdate::Invalid, "検索対象が2000件を超えています。条件を追加してください。" if overflow
    (result.is_a?(Array) ? result : result.limit(2000)).map(&:id)
  end
  def task_params
    params.require(:task).permit(:title, :description, :assignee, :starts_on, :due_on, :due_at, :status, :category, :lock_version)
  end
  def set_task
    @task = current_wedding.tasks.find(params[:id])
  end

  def load_planning_context
    @planning_items = current_wedding.planning_items.order(:position, :id).limit(200)
    @task_planning_links = @task&.task_planning_links&.includes(:planning_item)&.order(:id) || []
  end

  def planning_item_from_param
    return if params[:planning_item_id].blank?

    current_wedding.planning_items.find(params[:planning_item_id])
  end
end
