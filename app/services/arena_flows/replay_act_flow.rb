module ArenaFlows
  class ReplayActFlow
    def self.call(game:, act_number:)
      ActiveRecord::Base.transaction do
        target_act = game.acts.find_by!(number: act_number)
        snapshot   = target_act.world_state_snapshot
        raise ArgumentError, "No snapshot available for act #{act_number}" if snapshot.blank?

        # Drop all acts after target (cascades to their turns via dependent: destroy)
        game.acts.where("number > ?", act_number).destroy_all

        # In target act: keep only the prologue turn, drop everything else
        target_act.turns.where.not("options_payload @> ?", '{"prologue":true}').destroy_all

        # Drop the act-closing transition turn from the preceding act
        if act_number > 1
          prev_act = game.acts.find_by(number: act_number - 1)
          prev_act&.turns&.where("options_payload @> ?", '{"act_transition":true}')&.destroy_all
        end

        # Restore world state and game status
        game.update!(world_state: snapshot, status: "active")

        # Restore the correct hero for this act (walk YAML to find last defined hero at or before act N)
        scenario = ScenarioCatalog.find!(game.scenario_slug, locale: game.game_language)
        restore_hero!(game: game, scenario: scenario, act_number: act_number)

        # Delete saves that fall after the rewind point
        game.saves.where("act_number > ?", act_number)
            .or(game.saves.where(act_number: act_number).where("turn_number > 0"))
            .destroy_all

        # Reactivate target act
        target_act.update!(status: "active")

        game
      end
    end

    def self.restore_hero!(game:, scenario:, act_number:)
      acts_def = scenario["acts"].to_a.sort_by { |a| a["number"].to_i }
      hero_def  = scenario["hero"]
      acts_def.each do |act_def|
        break if act_def["number"].to_i > act_number
        hero_def = act_def["hero"] if act_def["hero"]
      end
      return unless hero_def

      hero = Hero.find_or_create_by!(slug: hero_def["slug"]) do |h|
        h.name        = hero_def["name"]
        h.description = hero_def["description"]
        h.sex         = hero_def["sex"]
      end
      game.update!(hero: hero)
    end
    private_class_method :restore_hero!
  end
end
