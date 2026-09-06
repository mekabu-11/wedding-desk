class TasksController < ApplicationController
  before_action :set_task, only: %i[edit update]
  def index
    @status = params[:status].presence_in(Task::STATUSES.keys)
    @tasks = current_wedding.tasks.includes(candidate: :document)
    @tasks = @status ? @tasks.where(status: @status) : @tasks.open_items
    @assignee = params[:assignee].presence_in(Task::ASSIGNEES.keys)
    @tasks = @tasks.where(assignee: @assignee) if @assignee
    @period = params[:period].presence_in(%w[week overdue])
    deadline = "COALESCE(due_on, (due_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Tokyo')::date)"
    if @period == "week"
      monday = Date.current.beginning_of_week
      @tasks = @tasks.where("(starts_on <= ? AND #{deadline} >= ?) OR (starts_on IS NULL AND #{deadline} BETWEEN ? AND ?)", monday + 6, monday, monday, monday + 6)
    elsif @period == "overdue"
      @tasks = @tasks.open_items.where("(due_on < ?) OR (due_at < ?)", Date.current, Time.current)
    end
    @page = [params[:page].to_i, 1].max
    @total_count = @tasks.count
    @tasks = @tasks.by_deadline.offset((@page - 1) * 30).limit(30)
  end
  def edit; end
  def new
    @task = current_wedding.tasks.new(origin: "manual")
  end
  def create
    @task = current_wedding.tasks.new(task_params.merge(origin: "manual"))
    if @task.save
      redirect_to tasks_path, notice: "タスクを追加しました。", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end
  def update
    if @task.update(task_params)
      redirect_to tasks_path, notice: "タスクを保存しました。", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_task_path(@task), alert: "別の操作で更新されています。最新の内容を確認して保存してください。"
  end
  private
  def task_params
    params.require(:task).permit(:title, :description, :assignee, :starts_on, :due_on, :due_at, :status, :category, :lock_version)
  end
  def set_task
    @task = current_wedding.tasks.find(params[:id])
  end
end
