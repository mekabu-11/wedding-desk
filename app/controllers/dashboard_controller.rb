class DashboardController < ApplicationController
  def show
    @pending = Candidate.joins(:document).where(documents: { wedding_id: current_wedding.id }, review_status: "pending").count
    @tasks = current_wedding.tasks.open_items.by_deadline.limit(5)
    @documents = current_wedding.documents.order(created_at: :desc).limit(5)
    @open_count = current_wedding.tasks.open_items.count
    @done_count = current_wedding.tasks.where(status: "done").count
  end
end
