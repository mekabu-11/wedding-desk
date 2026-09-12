class GuestsController < ApplicationController
  before_action :set_guest, only: %i[edit update destroy]

  def index
    @tab = params[:tab].presence_in(%w[individuals households seating gifts meals]) || "individuals"
    @search_query = params[:q].to_s.strip[0, 100]
    @attendance = params[:attendance].presence_in(Guest::ATTENDANCES.keys)
    @side = params[:side].presence_in(Guest::SIDES.keys)
    @invitation_status = params[:invitation_status].presence_in(Guest::INVITATION_STATUSES.keys)
    @household_filter = params[:household].presence_in(%w[assigned unassigned])
    @role = params[:role].presence_in(Guest::ROLES.keys)
    @page = [params[:page].to_i, 1].max
    case @tab
    when "individuals" then load_individuals
    when "households" then load_households
    when "seating" then load_seating
    when "gifts" then load_gifts
    when "meals" then load_meals
    end
  end

  def new
    @guest = current_wedding.guests.new(attendance: "unanswered", side: "unknown", age_group: "adult")
    load_form_options
  end

  def create
    @guest = current_wedding.guests.new(guest_params)
    @guest.change_event_actor = current_user
    if @guest.save
      redirect_to guests_path(tab: "individuals"), notice: "ゲストを追加しました。", status: :see_other
    else
      load_form_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_form_options
    @change_events = ChangeEvent.for_target(@guest).where(wedding_id: current_wedding.id).limit(10)
  end

  def update
    @guest.change_event_actor = current_user
    if @guest.update(guest_params)
      redirect_to guests_path(tab: "individuals"), notice: "ゲストを保存しました。", status: :see_other
    else
      load_form_options
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_guest_path(@guest), alert: "別の操作で更新されています。最新の内容を確認してください。"
  end

  def destroy
    @guest.change_event_actor = current_user
    @guest.destroy!
    redirect_to guests_path(tab: "individuals"), notice: "ゲストを削除しました。", status: :see_other
  end

  private

  def set_guest
    @guest = current_wedding.guests.find(params[:id])
  end

  def guest_params
    params.require(:guest).permit(:name, :household_id, :seating_table_id, :meal_set_id, :side, :relationship,
      :gender, :age_group, :attendance, :invitation_status, :allergies, :notes, :lock_version,
      roles: [])
  end

  def load_form_options
    @households = current_wedding.households.active.order(:id)
    @seating_tables = current_wedding.seating_tables.order(:id)
    @meal_sets = current_wedding.meal_sets.ordered
  end

  def load_individuals
    scope = current_wedding.guests.includes(:household, :seating_table).ordered
    scope = scope.where(attendance: @attendance) if @attendance
    scope = scope.where(side: @side) if @side
    scope = scope.where(invitation_status: @invitation_status) if @invitation_status
    scope = @household_filter == "assigned" ? scope.where.not(household_id: nil) : scope.where(household_id: nil) if @household_filter
    if @search_query.present? || @role.present?
      candidates = scope.limit(2_001).to_a
      @search_truncated = candidates.size > 2_000
      @guests_scope = candidates.select do |guest|
        (@search_query.blank? || searchable_guest?(guest, @search_query)) &&
          (@role.blank? || Array(guest.roles).include?(@role))
      end
      @guests = @guests_scope.slice((@page - 1) * 30, 30) || []
    else
      @guests_scope = scope
      @guests = scope.offset((@page - 1) * 30).limit(30)
    end
    @total_count = @guests_scope.size
  end

  def load_households
    scope = current_wedding.households.active.includes(:guests, :cash_gift_rule).order(:id)
    if @search_query.present?
      candidates = scope.limit(2_001).to_a
      @search_truncated = candidates.size > 2_000
      @households_scope = candidates.select { |household| searchable_household?(household, @search_query) }
      @households = @households_scope.slice((@page - 1) * 30, 30) || []
    else
      @households_scope = scope
      @households = scope.offset((@page - 1) * 30).limit(30)
    end
    @total_count = @households_scope.size
    @cash_gift_budget_items = current_wedding.budget_items.where(source_kind: "cash_gift", source_id: @households.map(&:id)).index_by(&:source_id)
    @cash_gift_rules = current_wedding.cash_gift_rules.order(:id)
  end

  def load_seating
    @total_count = current_wedding.seating_tables.count
    @seating_tables = current_wedding.seating_tables.includes(:guests).order(:id).offset((@page - 1) * 30).limit(30)
  end

  def load_gifts
    @gift_sets = current_wedding.gift_sets.includes(:gift_set_items).order(:id).limit(30)
    @total_count = current_wedding.gift_assignments.count
    @gift_assignments = current_wedding.gift_assignments.includes(:household, :gift_set, :budget_item).order(:id).offset((@page - 1) * 30).limit(30)
    @guest_gift_assignments = current_wedding.guest_gift_assignments.includes(:guest, :gift_set, :budget_item).order(:id).limit(100)
  end

  def load_meals
    @meal_sets = current_wedding.meal_sets.ordered
    @meal_set_counts = MealSet.attending_guest_counts(current_wedding, @meal_sets)
    @meal_budget_items = current_wedding.budget_items.where(source_kind: "meal_set", source_id: @meal_sets.map(&:id)).index_by(&:source_id)
    @meal_guest_overrides = current_wedding.guests.includes(:meal_set).where.not(meal_set_id: nil).ordered
    @total_count = @meal_sets.size
  end

  def searchable_guest?(guest, query)
    [guest.name, guest.relationship, guest.allergies, guest.notes, guest.household&.name].compact.any? { |value| value.to_s.downcase.include?(query.downcase) }
  end

  def searchable_household?(household, query)
    [household.name, household.code, household.notes].compact.any? { |value| value.to_s.downcase.include?(query.downcase) }
  end
end
