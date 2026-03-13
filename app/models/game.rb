class Game < ApplicationRecord
  belongs_to :hero
  belongs_to :user, optional: true
  has_many :acts, dependent: :destroy
  has_many :turns, dependent: :destroy
  has_many :saves, dependent: :destroy
  has_many :impressions, dependent: :destroy

  validates :status, inclusion: { in: %w[active completed failed] }
  validates :game_language, inclusion: { in: I18n.available_locales.map(&:to_s) }
  validates :mode, inclusion: { in: %w[scenario random] }

  def arena_scenario?
    scenario_slug.present?
  end

  def random_mode?
    mode == "random"
  end

  def current_act
    acts.where(status: "active").order(:number).last
  end
end
