class GameService
  def self.start_game(scenario_slug:, hero_id: nil, game_language: I18n.default_locale.to_s)
    scenario = ScenarioCatalog.find!(scenario_slug)

    if scenario.present?
      ArenaFlows::StartScenarioFlow.call(
        scenario_slug: scenario_slug,
        hero_id: hero_id,
        game_language: game_language
      )
    else
      raise NotImplementedError, I18n.t("services.game_service.unsupported_scenario")
    end
  end

  def self.continue_turn(game:, action:)
    if game.arena_scenario?
      ArenaFlows::ContinueTurnFlow.call(game: game, action: action)
    else
      GameFlows::ContinueTurnFlow.call(game: game, action: action)
    end
  end
end
