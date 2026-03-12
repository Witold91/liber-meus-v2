module ArenaFlows
  class SaveGameFlow
    def self.call(game:, user:)
      world_state = game.world_state
      act_number  = world_state["act_number"] || game.current_act&.number || 1
      turn_number = game.turns.maximum(:turn_number) || 0

      label = "Act #{act_number}, Turn #{turn_number}"

      save = Save.find_or_initialize_by(game: game, user: user)
      save.assign_attributes(
        hero_id: game.hero_id,
        world_state: world_state.deep_dup,
        memory_summary: game.memory_summary,
        act_number: act_number,
        turn_number: turn_number,
        label: label
      )
      save.save!
      save
    end
  end
end
