class Impression < ApplicationRecord
  belongs_to :game
  has_neighbors :embedding

  validates :subject_type, inclusion: { in: %w[actor scene memory] }
  validates :fact, presence: true
  validates :turn_number, presence: true
end
