module RandomFlows
  class StartRandomGameFlow
    def self.call(world_data:, hero_data:, game_language: "en", user: nil)
      hero = Hero.find_or_create_by!(slug: hero_data["slug"]) do |h|
        h.name = hero_data["name"]
        h.description = hero_data["description_display"] || hero_data["description"]
        h.sex = hero_data["sex"]
      end

      initial_scene = world_data["initial_scene"]
      scene_id = initial_scene["id"]

      # Build actors/objects state from initial scene
      actors = {}
      (initial_scene["actors"] || []).each do |actor|
        actors[actor["id"]] = {
          "scene" => actor["scene"] || scene_id,
          "status" => actor["default_status"]
        }
      end

      objects = {}
      (initial_scene["objects"] || []).each do |obj|
        objects[obj["id"]] = {
          "scene" => obj["scene"] || scene_id,
          "status" => obj["default_status"]
        }
      end

      # Place starting equipment in player inventory
      starting_equipment = hero_data["starting_equipment"] || []
      starting_equipment.each do |item|
        objects[item["id"]] = {
          "scene" => "player_inventory",
          "status" => item["status"] || "equipped"
        }
        # Register in initial scene definition so WorldPresenter.objects can find them
        initial_scene["objects"] ||= []
        initial_scene["objects"] << {
          "id" => item["id"],
          "name" => item["name"],
          "scene" => scene_id,
          "default_status" => item["status"] || "equipped"
        }
      end

      world_state = OutcomeResolutionService.initial_state.merge(
        "act_number" => 1,
        "act_turn" => 0,
        "player_scene" => scene_id,
        "actors" => actors,
        "objects" => objects,
        "world_context" => world_data["world_context"],
        "world_context_display" => world_data["world_context_display"],
        "hero_description" => hero_data["description"],
        "narrator_style" => world_data["narrator_style"],
        "setting_name" => world_data["setting_name"],
        "theme" => RandomMode::WorldGeneratorService.resolve_theme(world_data["theme_id"]),
        "generated_scenes" => {
          scene_id => initial_scene
        }
      )

      game = Game.create!(
        hero: hero,
        scenario_slug: nil,
        mode: "random",
        world_state: world_state,
        game_language: game_language,
        status: "active",
        user: user
      )

      act = Act.create!(
        game: game,
        number: 1,
        status: "active",
        world_state_snapshot: world_state
      )

      presenter = RandomMode::WorldPresenter.new(world_state)
      scene_context = presenter.scene_context_for(scene_id, world_state)

      prologue, prologue_tokens = ArenaNarratorService.narrate_prologue(
        scene_context, world_data["world_context"],
        world_context: world_data["world_context"],
        narrator_style: world_data["narrator_style"]
      )

      TurnPersistenceService.create!(
        game: game,
        act: act,
        content: prologue["narrative"].to_s,
        llm_memory: prologue["memory_note"],
        turn_number: 0,
        tokens_used: prologue_tokens,
        options_payload: { "prologue" => true }
      )

      game
    end
  end
end
