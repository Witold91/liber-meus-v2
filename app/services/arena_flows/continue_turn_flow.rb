module ArenaFlows
  class ContinueTurnFlow
    def self.call(game:, action:)
      ActiveRecord::Base.transaction do
        # Step 1: Load scenario
        scenario = ScenarioCatalog.find!(game.scenario_slug, locale: game.game_language)
        world_state = game.world_state

        # Step 2: Determine turn number
        turn_number = (game.turns.maximum(:turn_number) || 0) + 1

        # Step 3: Get current act
        act = game.current_act
        raise I18n.t("services.arena_flows.continue_turn.no_active_act") unless act
        act_number = world_state["act_number"] || act.number || 1
        act_turn_number = world_state["act_turn"].to_i + 1

        # Step 4: Build scene context
        presenter = Arena::ScenarioPresenter.new(scenario, act_number, world_state)
        player_scene = world_state["player_scene"] || presenter.scenes.first&.dig("id")
        scene_context = presenter.scene_context_for(player_scene, world_state)

        # Step 5: Rate difficulty (AI call 1)
        recent_actions = game.turns.recent(3).to_a.reverse
                             .map { |t| { turn_number: t.turn_number, action: t.option_selected, resolution: t.resolution_tag } }
        rating, difficulty_tokens = DifficultyRatingService.rate(action, scene_context, game.hero, recent_actions, world_context: scenario["world_context"])
        difficulty = rating["difficulty"]
        rating_reasoning = rating["reasoning"]

        # Step 6: Resolve outcome (deterministic)
        intent = {
          difficulty: difficulty,
          danger: rating["danger"] || "none",
          impact: rating["impact"] || "positive"
        }
        outcome = OutcomeResolutionService.resolve(game, action, turn_number, intent)
        resolution_tag = outcome[:resolution_tag]

        # Reload world_state after outcome update
        game.reload
        world_state = game.world_state

        # Step 7: Get narration (AI call 2)
        turn_context = {
          world_state_delta: presenter.world_state_delta,
          memory_notes: game.turns.where.not(llm_memory: [ nil, "" ]).order(:turn_number)
                            .map { |t| { turn_number: t.turn_number, note: t.llm_memory } },
          recent_actions: recent_actions,
          rating_reasoning: rating_reasoning
        }
        narration, narrator_tokens = ArenaNarratorService.narrate(action, resolution_tag, difficulty, scene_context, turn_context, outcome[:health_loss], world_context: scenario["world_context"], narrator_style: scenario["narrator_style"])

        # Step 8: Apply world-state diff from narration
        diff = narration["diff"] || {}
        world_state = Arena::WorldStateManager.new(world_state).apply_scene_diff(diff, scenario: scenario)

        # Step 9: Apply scenario events
        ScenarioEventService.events_for_turn(turn_number: turn_number, act_turn_number: act_turn_number, world_state: world_state).each do |event|
          event_diff = ScenarioEventService.event_to_scene_diff(event)
          next if event_diff.empty?
          world_state = Arena::WorldStateManager.new(world_state).apply_scene_diff(event_diff, scenario: scenario)
        end
        world_state["act_turn"] = act_turn_number

        # Persist updated world state
        game.update!(world_state: world_state)

        # Step 10: Persist turn
        llm_memory = narration["memory_note"]
        narrative_content = narration["narrative"] || ""
        tokens_used = difficulty_tokens + narrator_tokens

        turn = TurnPersistenceService.create!(
          game: game,
          act: act,
          content: narrative_content,
          turn_number: turn_number,
          option_selected: action,
          resolution_tag: resolution_tag,
          llm_memory: llm_memory,
          tokens_used: tokens_used
        )

        # Step 11: Check end conditions
        end_condition = EndConditionChecker.check(turn_number, world_state, scenario)
        if end_condition
          epilogue_narration, epilogue_tokens = ArenaNarratorService.narrate_epilogue(
            scene_context, action, resolution_tag,
            end_condition["narrative"].to_s,
            world_context: scenario["world_context"],
            narrator_style: scenario["narrator_style"]
          )
          epilogue_content = epilogue_narration["narrative"].to_s

          if transition_to_next_act?(end_condition: end_condition, scenario: scenario, act_number: act_number)
            next_act_number = resolve_next_act_number(end_condition: end_condition, act_number: act_number)

            # Act-closing turn (AI epilogue for current act)
            TurnPersistenceService.create!(
              game: game,
              act: act,
              content: epilogue_content,
              turn_number: turn_number + 1,
              tokens_used: epilogue_tokens,
              options_payload: {
                "ending" => true,
                "ending_status" => "completed",
                "ending_condition_id" => end_condition["id"],
                "act_transition" => true,
                "next_act_number" => next_act_number
              }
            )

            advance_act!(game: game, scenario: scenario, world_state: world_state, current_act: act, next_act_number: next_act_number)
            next_act = game.acts.find_by!(number: next_act_number)
            game.reload
            new_world_state = game.world_state
            new_presenter = Arena::ScenarioPresenter.new(scenario, next_act_number, new_world_state)
            new_scene_context = new_presenter.scene_context_for(new_world_state["player_scene"], new_world_state)
            next_act_intro = scenario["acts"]&.find { |a| a["number"] == next_act_number }&.dig("intro").to_s

            act_prologue, act_prologue_tokens = ArenaNarratorService.narrate_prologue(
              new_scene_context, next_act_intro,
              world_context: scenario["world_context"],
              narrator_style: scenario["narrator_style"]
            )

            # New act prologue turn (AI-generated opening for next act)
            TurnPersistenceService.create!(
              game: game,
              act: next_act,
              content: act_prologue["narrative"].to_s,
              llm_memory: act_prologue["memory_note"],
              turn_number: turn_number + 2,
              tokens_used: act_prologue_tokens,
              options_payload: {
                "prologue" => true,
                "act_number" => next_act_number
              }
            )
          else
            final_status = %w[goal act_goal].include?(end_condition["type"]) ? "completed" : "failed"

            TurnPersistenceService.create!(
              game: game,
              act: act,
              content: epilogue_content,
              turn_number: turn_number + 1,
              tokens_used: epilogue_tokens,
              options_payload: {
                "ending" => true,
                "ending_status" => final_status,
                "ending_condition_id" => end_condition["id"]
              }
            )

            game.update!(status: final_status)
            act.update!(status: "completed")
          end
        end

        turn
      end # transaction
    end

    def self.transition_to_next_act?(end_condition:, scenario:, act_number:)
      return false unless end_condition["type"] == "act_goal"
      next_act_number = resolve_next_act_number(end_condition: end_condition, act_number: act_number)
      scenario["acts"].to_a.any? { |a| a["number"] == next_act_number }
    end

    def self.resolve_next_act_number(end_condition:, act_number:)
      (end_condition["next_act"] || (act_number.to_i + 1)).to_i
    end

    def self.advance_act!(game:, scenario:, world_state:, current_act:, next_act_number:)
      current_act.update!(status: "completed")

      next_act = game.acts.find_or_create_by!(number: next_act_number) do |a|
        a.status = "active"
      end
      next_act.update!(status: "active")

      next_world_state = build_world_state_for_act(world_state: world_state, scenario: scenario, act_number: next_act_number)
      game.update!(world_state: next_world_state)
    end

    def self.build_world_state_for_act(world_state:, scenario:, act_number:)
      presenter = Arena::ScenarioPresenter.new(scenario, act_number, world_state)
      actors = presenter.actors.each_with_object({}) do |actor, h|
        h[actor["id"]] = { "scene" => actor["scene"], "status" => actor["default_status"] }
      end
      objects = presenter.objects.each_with_object({}) do |object, h|
        h[object["id"]] = { "scene" => object["scene"], "status" => object["default_status"] }
      end

      state = world_state.deep_dup
      state["act_number"] = act_number
      state["act_turn"] = 0
      state["player_scene"] = presenter.scenes.first&.dig("id")
      state["actors"] = actors
      state["objects"] = objects
      state
    end

    private_class_method :transition_to_next_act?, :resolve_next_act_number, :advance_act!, :build_world_state_for_act
  end
end
