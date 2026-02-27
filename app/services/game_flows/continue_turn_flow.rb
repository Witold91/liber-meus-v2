module GameFlows
  class ContinueTurnFlow
    def self.call(game:, action:)
      # Placeholder for non-arena game flow
      turn_number = (game.turns.maximum(:turn_number) || 0) + 1
      chapter = game.current_chapter

      TurnPersistenceService.create!(
        game: game,
        chapter: chapter,
        content: I18n.t("services.game_flows.continue_turn.not_implemented", action: action),
        turn_number: turn_number,
        option_selected: action,
        resolution_tag: "partial"
      )
    end
  end
end
