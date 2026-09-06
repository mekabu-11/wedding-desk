class TasksController < ApplicationController
  before_action :set_task, only: %i[edit update]
  def index
    @status = params[:status].presence_in(Task::STATUSES.keys)
    @tasks = current_wedding.tasks.includes(candidate: :document)
    @tasks = @status ? @tasks.where(status: @status) : @tasks.open_items
    @page = [params[:page].to_i, 1].max
    @total_count = @tasks.count
    @tasks = @tasks.by_deadline.offset((@page - 1) * 30).limit(30)
  end
  def edit; end
  def update
    if @task.update(params.require(:task).permit(:title, :description, :assignee, :due_on, :due_at, :status, :category, :lock_version))
      redirect_to tasks_path, notice: "タスクを保存しました。", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_task_path(@task), alert: "別の操作で更新されています。最新の内容を確認して保存してください。"
  end
  private
  def set_task
    @task = current_wedding.tasks.find(params[:id])
  end
end
