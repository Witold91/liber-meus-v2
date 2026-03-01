class Save < ApplicationRecord
  belongs_to :game
  belongs_to :user
  belongs_to :hero

  validates :act_number, :turn_number, :label, presence: true
end
