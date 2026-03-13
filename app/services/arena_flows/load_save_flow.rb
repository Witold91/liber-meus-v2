module ArenaFlows
  class LoadSaveFlow
    def self.call(game:, save:)
      raise ArgumentError, "Save does not belong to this game" unless save.game_id == game.id

      ActiveRecord::Base.transaction do
        saved_act_number  = save.act_number
        saved_turn_number = save.turn_number

        # Drop all acts after the saved act (cascades to their turns)
        game.acts.where("number > ?", saved_act_number).destroy_all

        # In the saved act: drop turns and impressions after the saved turn number
        target_act = game.acts.find_by!(number: saved_act_number)
        target_act.turns.where("turn_number > ?", saved_turn_number).destroy_all
        game.impressions.where("turn_number > ?", saved_turn_number).delete_all

        # Restore world state, hero, and game status
        game.update!(
          world_state: save.world_state,
          hero_id: save.hero_id,
          memory_summary: save.memory_summary,
          status: "active"
        )

        # Reactivate target act (may have been completed)
        target_act.update!(status: "active")

        game
      end
    end
  end
end
