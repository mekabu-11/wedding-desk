class DashboardController < ApplicationController
  def show
    @pending = Candidate.joins(:document).where(documents: { wedding_id: current_wedding.id }, review_status: "pending").count
    @tasks = current_wedding.tasks.open_items.by_deadline.limit(6)
    @documents = current_wedding.documents.order(created_at: :desc).limit(5)
    @open_count = current_wedding.tasks.open_items.count
    @done_count = current_wedding.tasks.where(status: "done").count
    monday = Date.current.beginning_of_week
    @week_count = current_wedding.tasks.open_items.where(
      "due_on BETWEEN :from AND :to OR due_at BETWEEN :from_time AND :to_time",
      from: monday, to: monday + 6.days, from_time: monday.beginning_of_day, to_time: (monday + 6.days).end_of_day
    ).count
    @overdue_count = current_wedding.tasks.open_items.where("due_on < ? OR due_at < ?", Date.current, Time.current).count
    @attendance_counts = current_wedding.guests.group(:attendance).count
    @considering_count = current_wedding.planning_options.where(status: "considering").count
    budget_items = current_wedding.budget_items.included.includes(:money_movements).to_a
    @unknown_amount_count = budget_items.count { |item| item.amount_yen.nil? }
    @income_total = budget_items.select { |item| item.direction == "income" }.sum { |item| item.amount_yen.to_i }
    @expense_total = budget_items.select { |item| item.direction == "expense" }.sum { |item| item.amount_yen.to_i }
    @estimated_burden = @expense_total - @income_total
    @outstanding_items = budget_items.select { |item| item.remaining_amount.to_i.positive? }
    @outstanding_amount = @outstanding_items.sum { |item| item.remaining_amount.to_i }
    @expense_total = budget_items.select { |item| item.direction == "expense" }.sum { |item| item.amount_yen.to_i }
    @estimated_burden = @expense_total - @income_total
    @outstanding_items = budget_items.select { |item| item.amount_yen && item.remaining_amount.to_i > 0 }
    @outstanding_amount = @outstanding_items.sum { |item| item.remaining_amount.to_i }
    @recent_changes = current_wedding.change_events.preload(:actor, :target).order(created_at: :desc).limit(8)
  end
end
