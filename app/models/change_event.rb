class ChangeEvent < ApplicationRecord
  belongs_to :wedding
  belongs_to :actor, class_name: "User", optional: true

  encrypts :before, :after, :source

  validates :target_type, :action, presence: true, length: { maximum: 80 }
  validates :target_id, numericality: { only_integer: true, greater_than: 0 }

  def self.record!(wedding:, target:, action:, before: nil, after: nil, source: nil, actor: nil)
    create!(wedding: wedding, actor: actor, target_type: target.class.name, target_id: target.id,
      action: action, before: before, after: after, source: source)
  end

  def self.for_target(target)
    where(target_type: target.class.name, target_id: target.id).order(created_at: :desc)
  end
end
