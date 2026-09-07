class PlanningCostLinksController < ApplicationController
  def create
    planning_item = current_wedding.planning_items.find(params.require(:planning_item_id))
    budget_item = current_wedding.budget_items.find(params.require(:budget_item_id))
    current_wedding.planning_cost_links.create!(planning_item: planning_item, budget_item: budget_item)
    redirect_to planning_item_path(planning_item), notice: "費用を紐付けました。", status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to planning_item_path(planning_item), alert: "費用を紐付けできませんでした。", status: :see_other
  end

  def destroy
    link = current_wedding.planning_cost_links.find(params[:id])
    item = link.planning_item
    link.destroy!
    redirect_to planning_item_path(item), notice: "費用の紐付けを解除しました。BudgetItemと履歴は残ります。", status: :see_other
  end
end
