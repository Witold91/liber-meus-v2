class Game < ApplicationRecord
  belongs_to :hero
  belongs_to :user, optional: true
  has_many :acts, dependent: :destroy
  has_many :turns, dependent: :destroy

  validates :status, inclusion: { in: %w[active completed failed] }
  validates :game_language, inclusion: { in: I18n.available_locales.map(&:to_s) }

  def arena_scenario?
    scenario_slug.present?
  end

  def current_act
    acts.where(status: "active").order(:number).last
  end
end
