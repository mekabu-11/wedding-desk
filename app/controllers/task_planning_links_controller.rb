class TaskPlanningLinksController < ApplicationController
  def create
    planning_item = current_wedding.planning_items.find(params.require(:planning_item_id))
    task = current_wedding.tasks.find(params.require(:task_id))
    current_wedding.task_planning_links.create!(planning_item: planning_item, task: task)
    redirect_back fallback_location: planning_item_path(planning_item), notice: "タスクを紐付けました。", status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_back fallback_location: planning_item_path(planning_item), alert: "タスクを紐付けできませんでした。", status: :see_other
  end

  def destroy
    link = current_wedding.task_planning_links.find(params[:id])
    fallback = planning_item_path(link.planning_item)
    link.destroy!
    redirect_back fallback_location: fallback, notice: "タスクの紐付けを解除しました。", status: :see_other
  end
end
