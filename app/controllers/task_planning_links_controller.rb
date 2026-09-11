class TaskPlanningLinksController < ApplicationController
  def create
    planning_item = current_wedding.planning_items.find(params.require(:planning_item_id))
    task = current_wedding.tasks.find(params.require(:task_id))
    ActiveRecord::Base.transaction do
      current_wedding.task_planning_links.create!(planning_item: planning_item, task: task)
      record_change!(planning_item, "task_planning_link_created", after: { task_id: task.id, task_title: task.title })
    end
    redirect_back fallback_location: planning_item_path(planning_item), notice: "タスクを紐付けました。", status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_back fallback_location: planning_item_path(planning_item), alert: "タスクを紐付けできませんでした。", status: :see_other
  end

  def destroy
    link = current_wedding.task_planning_links.find(params[:id])
    fallback = planning_item_path(link.planning_item)
    item = link.planning_item
    task = link.task
    ActiveRecord::Base.transaction do
      link.destroy!
      record_change!(item, "task_planning_link_deleted", before: { task_id: task.id, task_title: task.title })
    end
    redirect_back fallback_location: fallback, notice: "タスクの紐付けを解除しました。", status: :see_other
  end
end
