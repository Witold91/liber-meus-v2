module RandomFlows
  class ContinueTurnFlow
    extend TurnFlowSteps

    NARRATOR_PROMPT_PATH = Rails.root.join("lib", "prompts", "random_narrator.txt")

    def self.call(game:, action:, stream: nil)
      # Steps 1-6: AI calls and resolution (outside transaction)
      world_state = game.world_state

      # Step 1: Determine turn number
      turn_number = game.next_turn_number

      # Step 2: Get current act
      act = game.current_act
      raise "No active act found for random game" unless act
      act_turn_number = world_state["act_turn"].to_i + 1

      # Step 3: Build scene context
      presenter = RandomMode::WorldPresenter.new(world_state)
      player_scene = world_state["player_scene"]
      scene_context = presenter.scene_context_for(player_scene, world_state)

      # Step 3.5: Retrieve established facts (vector impressions)
      established_facts = ImpressionService.retrieve(
        game: game, scene_id: player_scene,
        actor_ids: scene_context[:actors].map { |a| a[:id] },
        action_text: action
      )

      # Step 4: Rate difficulty (AI call 1)
      recent_actions = fetch_recent_actions(game)
      memory_notes = fetch_memory_notes(game)
      rating, difficulty_tokens = rate_difficulty(
        action, scene_context, game.hero, recent_actions,
        world_context: world_state["world_context"],
        memory_summary: game.memory_summary,
        memory_notes: memory_notes,
        current_hp: world_state["health"],
        established_facts: established_facts
      )
      difficulty = rating["difficulty"]
      rating_reasoning = rating["reasoning"]

      # Step 5: Resolve outcome (deterministic)
      momentum_at_roll = world_state["momentum"].to_i
      outcome = resolve_outcome(game, action, turn_number, rating)
      resolution_tag = outcome[:resolution_tag]

      # Broadcast roll result immediately so player sees it while narrative streams
      broadcast_roll(stream, outcome, difficulty, momentum_at_roll)

      # Reload world_state after outcome update
      game.reload
      world_state = game.world_state

      # Step 6: Get narration (AI call 2 — streams narrative chunks if callback provided)
      last_turn = game.turns.recent(1).first
      previous_narrative_tail = last_turn&.content&.then { |c| c.lines.last(5).join } || ""

      turn_context = build_turn_context(presenter, game, recent_actions, rating_reasoning, previous_narrative_tail, established_facts)
      narration, narrator_tokens = ArenaNarratorService.narrate(
        action, resolution_tag, difficulty, scene_context, turn_context, outcome[:health_loss],
        world_context: world_state["world_context"],
        narrator_style: world_state["narrator_style"],
        prompt_path: NARRATOR_PROMPT_PATH,
        stream: stream&.dig(:on_chunk),
        hero: game.hero,
        turn_number: turn_number,
        random_mode: true,
        current_hp: world_state["health"],
        health_gain: outcome[:health_gain]
      )

      # Store impressions from narration (non-fatal, outside transaction)
      ImpressionService.store!(
        game: game, turn_number: turn_number,
        impressions_data: narration["impressions"],
        memory_note: narration["memory_note"]
      )

      # Steps 7-10: DB writes (in transaction)
      turn = ActiveRecord::Base.transaction do
        # Step 7: Apply world-state diff from narration
        diff = narration["diff"] || {}
        world_state = Arena::WorldStateManager.new(world_state).apply_scene_diff(diff, presenter: presenter)

        # Step 8: Generate new scene if player moved to unknown location
        new_player_scene = world_state["player_scene"]
        generated_scenes = world_state["generated_scenes"] || {}
        if new_player_scene && !generated_scenes.key?(new_player_scene)
          world_state = generate_new_scene(game, world_state, player_scene, new_player_scene, diff)
        end

        # Track recently visited scenes for context
        visited = world_state["recently_visited_scenes"] ||= []
        new_scene = world_state["player_scene"]
        visited.delete(new_scene)
        visited << new_scene
        world_state["recently_visited_scenes"] = visited.last(10)

        world_state["act_turn"] = act_turn_number

        # Persist updated world state
        game.update!(world_state: world_state)

        # Step 9: Persist turn
        llm_memory = narration["memory_note"]
        narrative_content = narration["narrative"] || ""
        tokens_used = difficulty_tokens + narrator_tokens
        roll_payload = build_roll_payload(outcome, difficulty, momentum_at_roll, rating)

        turn = Turn.create!(
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

        # Step 9.5: Compress memory if threshold reached
        MemoryCompressionService.maybe_compress!(game)

        # Step 10: Check health depletion (only end condition in random mode)
        if world_state["health"].to_i <= 0
          epilogue_narration, epilogue_tokens = ArenaNarratorService.narrate_epilogue(
            scene_context, action, resolution_tag,
            "The hero has fallen. Their journey ends here.",
            world_context: world_state["world_context"],
            narrator_style: world_state["narrator_style"]
          )

          Turn.create!(
            game: game,
            act: act,
            content: epilogue_narration["narrative"].to_s,
            turn_number: turn_number + 1,
            tokens_used: epilogue_tokens,
            options_payload: {
              "ending" => true,
              "ending_status" => "failed"
            }
          )

          game.update!(status: "failed")
          act.update!(status: "completed")
        end

        turn
      end # transaction

      # Deduct all tokens used in this turn from user's budget
      deduct_user_tokens(game, turn_number..(turn_number + 1))

      turn
    end

    def self.generate_new_scene(game, world_state, origin_scene_id, target_scene_id, diff)
      generated_scenes = world_state["generated_scenes"] || {}

      exit_label = target_scene_id.to_s.tr("_", " ")

      # Gather context
      presenter = RandomMode::WorldPresenter.new(world_state)
      inventory = presenter.send(:player_inventory, world_state)
      memory_notes = fetch_memory_notes(game)

      scene_data, _tokens = RandomMode::SceneGeneratorService.generate(
        world_context: world_state["world_context"],
        existing_scenes: generated_scenes.values,
        origin_scene_id: origin_scene_id,
        exit_label: exit_label,
        player_inventory: inventory,
        memory_notes: memory_notes,
        game_language: game.game_language
      )

      # Use the target scene ID if the generator gave a different one
      scene_data["id"] = target_scene_id

      # Store the new scene
      world_state["generated_scenes"] ||= {}
      world_state["generated_scenes"][target_scene_id] = scene_data

      # Initialize actors/objects from the new scene
      (scene_data["actors"] || []).each do |actor|
        world_state["actors"] ||= {}
        world_state["actors"][actor["id"]] ||= {
          "scene" => actor["scene"] || target_scene_id,
          "status" => actor["default_status"]
        }
      end

      (scene_data["objects"] || []).each do |obj|
        world_state["objects"] ||= {}
        world_state["objects"][obj["id"]] ||= {
          "scene" => obj["scene"] || target_scene_id,
          "status" => obj["default_status"]
        }
      end

      # Update player scene
      world_state["player_scene"] = target_scene_id

      world_state
    end
    private_class_method :generate_new_scene
  end
end
