class User < ApplicationRecord
  has_many :games, dependent: :nullify
  has_many :saves, dependent: :destroy

  validates :email,      presence: true, uniqueness: true
  validates :google_uid, presence: true, uniqueness: true
end
