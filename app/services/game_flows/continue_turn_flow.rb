module GameFlows
  class ContinueTurnFlow
    def self.call(game:, action:)
      # Placeholder for non-arena game flow
      turn_number = game.next_turn_number
      act = game.current_act

      Turn.create!(
        game: game,
        act: act,
        content: I18n.t("services.game_flows.continue_turn.not_implemented", action: action),
        turn_number: turn_number,
        option_selected: action,
        resolution_tag: "partial"
      )
    end
  end
end
