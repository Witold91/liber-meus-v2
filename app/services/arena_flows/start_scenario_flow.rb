module ArenaFlows
  class StartScenarioFlow
    def self.call(scenario_slug:, hero_id: nil, game_language: I18n.default_locale.to_s)
      scenario = ScenarioCatalog.find!(scenario_slug, locale: game_language)

      hero = find_or_create_hero(scenario, hero_id)

      world_state = build_initial_world_state(scenario, scenario_slug)

      game = Game.create!(
        hero: hero,
        scenario_slug: scenario_slug,
        world_state: world_state,
        game_language: game_language,
        status: "active"
      )

      act = Act.create!(
        game: game,
        number: 1,
        status: "active"
      )

      presenter = Arena::ScenarioPresenter.new(scenario, 1, world_state)
      scene_context = presenter.scene_context_for(world_state["player_scene"], world_state)
      act_intro = scenario["acts"]&.first&.dig("intro").to_s

      prologue, prologue_tokens = ArenaNarratorService.narrate_prologue(
        scene_context, act_intro,
        world_context: scenario["world_context"],
        narrator_style: scenario["narrator_style"]
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

    private

    def self.find_or_create_hero(scenario, hero_id)
      return Hero.find(hero_id) if hero_id.present?

      hero_def = scenario["hero"]
      raise ArgumentError, I18n.t("services.arena_flows.start_scenario.missing_hero") unless hero_def

      Hero.find_or_create_by!(slug: hero_def["slug"]) do |h|
        h.name = hero_def["name"]
        h.description = hero_def["description"]
        h.sex = hero_def["sex"]
      end
    end

    def self.build_initial_world_state(scenario, scenario_slug)
      base = OutcomeResolutionService.initial_state
      presenter = Arena::ScenarioPresenter.new(scenario, 1, base)

      actors = {}
      presenter.actors.each do |actor|
        actors[actor["id"]] = {
          "scene" => actor["scene"],
          "status" => actor["default_status"]
        }
      end

      objects = {}
      presenter.objects.each do |obj|
        objects[obj["id"]] = {
          "scene" => obj["scene"],
          "status" => obj["default_status"]
        }
      end

      first_scene = presenter.scenes.first&.dig("id")

      base.merge(
        "scenario_slug" => scenario_slug,
        "act_number" => 1,
        "act_turn" => 0,
        "player_scene" => first_scene,
        "actors" => actors,
        "objects" => objects
      )
    end
  end
end
