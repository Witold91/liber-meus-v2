module ArenaFlows
  class ContinueTurnFlow
    def self.call(game:, action:, stream: nil)
      # Steps 1-7: AI calls and resolution (outside transaction)

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

      # Step 4.5: Retrieve established facts (vector impressions)
      established_facts = ImpressionService.retrieve(
        game: game, scene_id: player_scene,
        actor_ids: scene_context[:actors].map { |a| a[:id] },
        action_text: action
      )

      # Step 5: Rate difficulty (AI call 1)
      recent_actions = game.turns.recent(3).to_a.reverse
                           .map { |t| { turn_number: t.turn_number, action: t.option_selected, resolution: t.resolution_tag } }
      memory_notes = game.turns.where.not(llm_memory: [nil, ""]).order(:turn_number)
                         .map { |t| { turn_number: t.turn_number, note: t.llm_memory } }
      rating, difficulty_tokens = DifficultyRatingService.rate(action, scene_context, game.hero, recent_actions, world_context: scenario["world_context"], memory_summary: game.memory_summary, memory_notes: memory_notes, current_hp: world_state["health"], established_facts: established_facts)
      difficulty = rating["difficulty"]
      rating_reasoning = rating["reasoning"]

      # Step 6: Resolve outcome (deterministic)
      momentum_at_roll = world_state["momentum"].to_i
      intent = {
        difficulty: difficulty,
        danger: rating["danger"] || "none",
        impact: rating["impact"] || "positive",
        stance: rating["stance"] || rating["exposure"] || "active",
        healing: rating["healing"] == true
      }
      outcome = OutcomeResolutionService.resolve(game, action, turn_number, intent)
      resolution_tag = outcome[:resolution_tag]

      # Broadcast roll result immediately so player sees it while narrative streams
      if stream&.dig(:on_roll)
        stream[:on_roll].call(
          roll: outcome[:roll],
          difficulty: difficulty,
          momentum: momentum_at_roll,
          resolution_tag: resolution_tag,
          health_loss: outcome[:health_loss],
          health_gain: outcome[:health_gain]
        )
      end

      # Reload world_state after outcome update
      game.reload
      world_state = game.world_state

      # Step 6.5: Collect turn-triggered event descriptions for narrator context
      turn_events = ScenarioEventService.events_for_turn(
        turn_number: turn_number, act_turn_number: act_turn_number, world_state: world_state, locale: game.game_language
      ).reject { |e| e.key?("trigger") }
      event_descriptions = turn_events.filter_map { |e| e["description"] }

      # Step 7: Get narration (AI call 2 — streams narrative chunks if callback provided)
      encountered_actors = world_state["encountered_actors"] || []
      current_scene_actor_ids = scene_context[:actors].map { |a| a[:id] }

      last_turn = game.turns.recent(1).first
      previous_narrative_tail = last_turn&.content&.then { |c| c.lines.last(5).join } || ""

      turn_context = {
        world_state_delta: presenter.world_state_delta,
        memory_summary: game.memory_summary,
        memory_notes: game.turns.where.not(llm_memory: [ nil, "" ]).order(:turn_number)
                          .map { |t| { turn_number: t.turn_number, note: t.llm_memory } },
        recent_actions: recent_actions,
        rating_reasoning: rating_reasoning,
        previous_narrative_tail: previous_narrative_tail.presence,
        established_facts: established_facts
      }
      narration, narrator_tokens = ArenaNarratorService.narrate(action, resolution_tag, difficulty, scene_context, turn_context, outcome[:health_loss], world_context: scenario["world_context"], narrator_style: scenario["narrator_style"], event_descriptions: event_descriptions, stream: stream&.dig(:on_chunk), hero: game.hero, turn_number: turn_number, random_mode: game.random_mode?, encountered_actors: encountered_actors, current_hp: world_state["health"], health_gain: outcome[:health_gain])

      # Store impressions from narration (non-fatal, outside transaction)
      ImpressionService.store!(
        game: game, turn_number: turn_number,
        impressions_data: narration["impressions"],
        memory_note: narration["memory_note"]
      )

      # Steps 8-11: DB writes (in transaction)
      turn = ActiveRecord::Base.transaction do
        # Step 8: Apply world-state diff from narration
        diff = narration["diff"] || {}
        world_state = Arena::WorldStateManager.new(world_state).apply_scene_diff(diff, scenario: scenario)

        # Step 9: Apply scenario events
        new_event_memories = []
        ScenarioEventService.events_for_turn(
          turn_number: turn_number,
          act_turn_number: act_turn_number,
          world_state: world_state,
          locale: game.game_language
        ).each do |event|
          event_diff = ScenarioEventService.event_to_scene_diff(event)
          next if event_diff.empty?
          world_state = Arena::WorldStateManager.new(world_state).apply_scene_diff(event_diff, scenario: scenario)
          if event.key?("trigger")
            world_state["fired_events"] ||= []
            world_state["fired_events"] |= [ event["id"] ]
            new_event_memories << event["description"] if event["description"].present?
          end
        end
        world_state["act_turn"] = act_turn_number
        world_state["encountered_actors"] = (encountered_actors | current_scene_actor_ids).uniq

        # Persist updated world state
        game.update!(world_state: world_state)

        # Step 10: Persist turn
        llm_memory = narration["memory_note"]
        if new_event_memories.any?
          llm_memory = [ llm_memory, *new_event_memories ].compact.join(" | ")
        end
        narrative_content = narration["narrative"] || ""
        tokens_used = difficulty_tokens + narrator_tokens

        roll_payload = { "roll" => outcome[:roll], "difficulty" => difficulty, "momentum_at_roll" => momentum_at_roll, "health_loss" => outcome[:health_loss], "damage_dice" => outcome[:damage_dice], "health_gain" => outcome[:health_gain], "healing_dice" => outcome[:healing_dice], "stance" => rating["stance"] || rating["exposure"] || "active" }

        turn = TurnPersistenceService.create!(
          game: game,
          act: act,
          content: narrative_content,
          turn_number: turn_number,
          option_selected: action,
          resolution_tag: resolution_tag,
          llm_memory: llm_memory,
          tokens_used: tokens_used,
          options_payload: roll_payload
        )

        # Step 10.5: Compress memory if threshold reached
        MemoryCompressionService.maybe_compress!(game)

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

      # Deduct all tokens used in this turn (main + any epilogue/prologue) from user's budget
      if game.user.present?
        all_tokens = game.turns.where(turn_number: turn_number..(turn_number + 2)).sum(:tokens_used)
        game.user.deduct_tokens!(all_tokens)
      end

      turn
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

      # Switch protagonist if the new act defines its own hero
      next_act_def = scenario["acts"]&.find { |a| a["number"] == next_act_number }
      if (hero_def = next_act_def&.dig("hero"))
        next_hero = Hero.find_or_create_by!(slug: hero_def["slug"]) do |h|
          h.name            = hero_def["name"]
          h.description     = hero_def["description"]
          h.llm_description = hero_def["llm_description"]
          h.sex             = hero_def["sex"]
        end
        game.update!(hero: next_hero)
      end

      next_world_state = build_world_state_for_act(world_state: world_state, scenario: scenario, act_number: next_act_number)
      next_act.update!(status: "active", world_state_snapshot: next_world_state)
      game.update!(world_state: next_world_state)
    end

    def self.build_world_state_for_act(world_state:, scenario:, act_number:)
      presenter = Arena::ScenarioPresenter.new(scenario, act_number, world_state)
      previous_actors = world_state["actors"] || {}
      previous_objects = world_state["objects"] || {}

      # Start with carried-over entries for actors/objects not in the new act
      # (so statuses survive even if an actor skips an act entirely)
      actors = previous_actors.dup
      objects = previous_objects.dup

      # Layer on the new act's definitions
      # Priority: force_status > carried-over status > default_status
      presenter.actors.each do |actor|
        prev = previous_actors[actor["id"]]
        status = actor["force_status"] || (prev && prev["status"]) || actor["default_status"]
        disposition = (prev && prev["disposition"]) || actor["default_disposition"] || "neutral"
        actors[actor["id"]] = { "scene" => actor["scene"], "status" => status, "disposition" => disposition }
      end
      presenter.objects.each do |object|
        prev = previous_objects[object["id"]]
        status = object["force_status"] || (prev && prev["status"]) || object["default_status"]
        objects[object["id"]] = { "scene" => object["scene"], "status" => status }
      end

      state = world_state.deep_dup
      state["act_number"] = act_number
      state["act_turn"] = 0
      state["fired_events"] = []
      state["player_scene"] = presenter.scenes.first&.dig("id")
      state["actors"] = actors
      state["objects"] = objects
      state
    end

    private_class_method :transition_to_next_act?, :resolve_next_act_number, :advance_act!, :build_world_state_for_act
  end
end
