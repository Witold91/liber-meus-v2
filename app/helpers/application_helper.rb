module ApplicationHelper
  def game_title(game)
    if game.random_mode?
      game.world_state&.dig("setting_name") || "Random Adventure"
    else
      ScenarioCatalog.find(game.scenario_slug)&.dig("title") || game.scenario_slug
    end
  end

  DIFFICULTY_THRESHOLDS = { "easy" => 1, "medium" => 4, "hard" => 7 }.freeze

  def difficulty_threshold(difficulty)
    DIFFICULTY_THRESHOLDS[difficulty] || 4
  end
end
