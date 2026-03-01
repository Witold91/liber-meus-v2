class User < ApplicationRecord
  has_many :games, dependent: :nullify

  validates :email,      presence: true, uniqueness: true
  validates :google_uid, presence: true, uniqueness: true
end
