class Membership < ApplicationRecord
  ROLES = { "owner" => "管理者", "editor" => "メンバー" }.freeze

  belongs_to :user, inverse_of: :membership
  belongs_to :wedding, inverse_of: :memberships

  validates :role, inclusion: { in: ROLES.keys }
  validates :user_id, uniqueness: true
  validates :user_id, uniqueness: { scope: :wedding_id }
  validate :wedding_has_room, on: :create

  def owner?
    role == "owner"
  end

  private

  def wedding_has_room
    return unless wedding
    existing_members = Membership.where(wedding_id: wedding.id).where.not(id: id).count
    errors.add(:wedding, "に登録できるのは2人までです") if existing_members >= 2
  end
end
