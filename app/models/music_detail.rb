class MusicDetail < ApplicationRecord
  belongs_to :wedding
  belongs_to :planning_option

  encrypts :wish_track_a, :wish_track_b, :selected_track, :artist, :original_text, :scene

  validates :start_offset_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :same_wedding

  private

  def same_wedding
    errors.add(:planning_option, "結婚式が一致しません") if planning_option && planning_option.wedding_id != wedding_id
  end
end
