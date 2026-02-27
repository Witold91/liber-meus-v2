class Hero < ApplicationRecord
  has_many :games, dependent: :destroy

  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true
end
