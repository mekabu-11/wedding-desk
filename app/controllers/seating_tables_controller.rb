class SeatingTablesController < ApplicationController
  before_action :set_table, only: %i[edit update destroy]

  def new
    @seating_table = current_wedding.seating_tables.new
  end

  def create
    @seating_table = current_wedding.seating_tables.new(table_params)
    if @seating_table.save
      redirect_to guests_path(tab: "seating"), notice: "卓を追加しました。", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @seating_table.update(table_params)
      redirect_to guests_path(tab: "seating"), notice: "卓を保存しました。", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_seating_table_path(@seating_table), alert: "別の操作で更新されています。最新の内容を確認してください。"
  end

  def destroy
    @seating_table.destroy!
    redirect_to guests_path(tab: "seating"), notice: "卓を削除しました。", status: :see_other
  end

  private

  def set_table
    @seating_table = current_wedding.seating_tables.find(params[:id])
  end

  def table_params
    params.require(:seating_table).permit(:label, :capacity, :lock_version)
  end
end
