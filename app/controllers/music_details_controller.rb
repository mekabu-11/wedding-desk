class MusicDetailsController < ApplicationController
  before_action :set_option

  def create
    @music_detail = @option.build_music_detail(music_detail_params.merge(wedding: current_wedding))
    save_detail
  end

  def update
    @music_detail = @option.music_detail
    @music_detail.assign_attributes(music_detail_params)
    save_detail
  end

  private

  def set_option
    @option = current_wedding.planning_options.find(params[:planning_option_id])
  end

  def music_detail_params
    params.require(:music_detail).permit(:wish_track_a, :wish_track_b, :selected_track, :artist,
      :start_offset_seconds, :original_text, :scene, :lock_version)
  end

  def save_detail
    before = @music_detail.persisted? ? change_snapshot(@music_detail, :wish_track_a, :wish_track_b, :selected_track, :artist, :start_offset_seconds, :original_text, :scene) : nil
    saved = ActiveRecord::Base.transaction do
      result = @music_detail.save
      after = change_snapshot(@music_detail, :planning_option_id, :wish_track_a, :wish_track_b, :selected_track, :artist, :start_offset_seconds, :original_text, :scene)
      action = before ? "music_detail_updated" : "music_detail_created"
      record_change!(@music_detail, action, before: before, after: after) if result && (before.nil? || before != after.except("planning_option_id"))
      result
    end
    if saved
      redirect_to planning_item_path(@option.planning_item), notice: "BGM情報を保存しました。", status: :see_other
    else
      redirect_to planning_item_path(@option.planning_item), alert: "BGM情報を保存できませんでした。", status: :see_other
    end
  end
end
