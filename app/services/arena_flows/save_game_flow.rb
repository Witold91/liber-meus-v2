module ArenaFlows
  class SaveGameFlow
    def self.call(game:, user:)
      world_state = game.world_state
      act_number  = world_state["act_number"] || game.current_act&.number || 1
      turn_number = game.turns.maximum(:turn_number) || 0

      label = "Act #{act_number}, Turn #{turn_number}"

      Save.create!(
        game: game,
        user: user,
        hero_id: game.hero_id,
        world_state: world_state.deep_dup,
        act_number: act_number,
        turn_number: turn_number,
        label: label
      )
    end
  end
end
