class User < ApplicationRecord
  has_secure_password
  has_one :membership, dependent: :destroy, inverse_of: :user
  has_one :wedding, through: :membership
  normalizes :email, with: ->(value) { value.strip.downcase }
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 12 }, allow_nil: true
end
