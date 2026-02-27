class Turn < ApplicationRecord
  belongs_to :game
  belongs_to :chapter

  scope :recent, ->(n = 5) { order(turn_number: :desc).limit(n) }
end
