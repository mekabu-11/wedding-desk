class SeatingTablesController < ApplicationController
  before_action :set_table, only: %i[edit update destroy]

  def new
    @seating_table = current_wedding.seating_tables.new
  end

  def create
    @seating_table = current_wedding.seating_tables.new(table_params)
    saved = ActiveRecord::Base.transaction do
      result = @seating_table.save
      record_change!(@seating_table, "seating_table_created", after: change_snapshot(@seating_table, :label, :capacity)) if result
      result
    end
    if saved
      redirect_to guests_path(tab: "seating"), notice: "卓を追加しました。", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def layout
    @seating_tables = current_wedding.seating_tables.includes(:guests).order(:id)
  end

  def layout_preview
    return head :not_found unless Rails.env.development?

    @seating_layout_preview = true
    @seating_tables = 4.times.map do |index|
      current_wedding.seating_tables.new(id: -(index + 1), label: "QA#{index + 1}", capacity: 8)
    end
  end

  def update_layout
    positions = params.permit(positions: {}).fetch(:positions, {})
    tables = current_wedding.seating_tables.where(id: positions.keys).index_by { |table| table.id.to_s }
    return redirect_to layout_seating_tables_path, alert: "卓の配置を確認できませんでした。", status: :see_other if tables.keys.sort != positions.keys.sort

    SeatingTable.transaction do
      tables.each do |id, table|
        values = positions.fetch(id).permit(:x, :y)
        before = change_snapshot(table, :position_x, :position_y)
        table.update!(position_x: values[:x], position_y: values[:y])
        after = change_snapshot(table, :position_x, :position_y)
        record_change!(table, "seating_table_position_updated", before: before, after: after) if before != after
      end
    end
    redirect_to layout_seating_tables_path, notice: "卓の配置を保存しました。", status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError
    redirect_to layout_seating_tables_path, alert: "卓の配置を保存できませんでした。最新の画面でやり直してください。", status: :see_other
  end

  def update
    before = change_snapshot(@seating_table, :label, :capacity)
    saved = ActiveRecord::Base.transaction do
      result = @seating_table.update(table_params)
      after = change_snapshot(@seating_table, :label, :capacity)
      record_change!(@seating_table, "seating_table_updated", before: before, after: after) if result && before != after
      result
    end
    if saved
      redirect_to guests_path(tab: "seating"), notice: "卓を保存しました。", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_seating_table_path(@seating_table), alert: "別の操作で更新されています。最新の内容を確認してください。"
  end

  def destroy
    before = change_snapshot(@seating_table, :label, :capacity)
    ActiveRecord::Base.transaction do
      @seating_table.destroy!
      record_change!(@seating_table, "seating_table_deleted", before: before)
    end
    redirect_to guests_path(tab: "seating"), notice: "卓を削除しました。", status: :see_other
  end

  private

  def set_table
    @seating_table = current_wedding.seating_tables.find(params[:id])
  end

  def table_params
    params.require(:seating_table).permit(:label, :capacity, :position_x, :position_y, :lock_version)
  end
end
