class PlanningCostLinksController < ApplicationController
  def create
    planning_item = current_wedding.planning_items.find(params.require(:planning_item_id))
    budget_item = current_wedding.budget_items.find(params.require(:budget_item_id))
    ActiveRecord::Base.transaction do
      current_wedding.planning_cost_links.create!(planning_item: planning_item, budget_item: budget_item)
      record_change!(planning_item, "planning_cost_link_created", after: { budget_item_id: budget_item.id, budget_item_title: budget_item.title })
    end
    redirect_to planning_item_path(planning_item), notice: "費用を紐付けました。", status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    redirect_to planning_item_path(planning_item), alert: "費用を紐付けできませんでした。", status: :see_other
  end

  def destroy
    link = current_wedding.planning_cost_links.find(params[:id])
    item = link.planning_item
    budget_item = link.budget_item
    ActiveRecord::Base.transaction do
      link.destroy!
      record_change!(item, "planning_cost_link_deleted", before: { budget_item_id: budget_item.id, budget_item_title: budget_item.title })
    end
    redirect_to planning_item_path(item), notice: "費用の紐付けを解除しました。費用項目と入出金履歴は残ります。", status: :see_other
  end
end
