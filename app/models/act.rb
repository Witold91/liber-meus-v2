class Act < ApplicationRecord
  belongs_to :game
  has_many :turns, dependent: :destroy

  validates :number, presence: true
  validates :status, inclusion: { in: %w[active completed] }
end
