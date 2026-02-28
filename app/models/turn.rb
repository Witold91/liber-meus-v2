class Turn < ApplicationRecord
  belongs_to :game
  belongs_to :act

  scope :recent, ->(n = 5) { order(turn_number: :desc).limit(n) }
  scope :ending, -> { where("options_payload @> ?", '{"ending":true}') }
end
