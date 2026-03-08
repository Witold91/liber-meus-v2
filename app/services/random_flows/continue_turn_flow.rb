module RandomFlows
  class ContinueTurnFlow
    NARRATOR_PROMPT_PATH = Rails.root.join("lib", "prompts", "random_narrator.txt")

    def self.call(game:, action:)
      ActiveRecord::Base.transaction do
        world_state = game.world_state

        # Step 1: Determine turn number
        turn_number = (game.turns.maximum(:turn_number) || 0) + 1

        # Step 2: Get current act
        act = game.current_act
        raise "No active act found for random game" unless act
        act_turn_number = world_state["act_turn"].to_i + 1

        # Step 3: Build scene context
        presenter = RandomMode::WorldPresenter.new(world_state)
        player_scene = world_state["player_scene"]
        scene_context = presenter.scene_context_for(player_scene, world_state)

        # Step 4: Rate difficulty (AI call 1)
        recent_actions = game.turns.recent(3).to_a.reverse
                             .map { |t| { turn_number: t.turn_number, action: t.option_selected, resolution: t.resolution_tag } }
        rating, difficulty_tokens = DifficultyRatingService.rate(
          action, scene_context, game.hero, recent_actions,
          world_context: world_state["world_context"]
        )
        difficulty = rating["difficulty"]
        rating_reasoning = rating["reasoning"]

        # Step 5: Resolve outcome (deterministic)
        momentum_at_roll = world_state["momentum"].to_i
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

        # Step 6: Get narration (AI call 2) — uses random narrator prompt
        turn_context = {
          world_state_delta: presenter.world_state_delta,
          memory_notes: game.turns.where.not(llm_memory: [ nil, "" ]).order(:turn_number)
                            .map { |t| { turn_number: t.turn_number, note: t.llm_memory } },
          recent_actions: recent_actions,
          rating_reasoning: rating_reasoning
        }
        narration, narrator_tokens = ArenaNarratorService.narrate(
          action, resolution_tag, difficulty, scene_context, turn_context, outcome[:health_loss],
          world_context: world_state["world_context"],
          narrator_style: world_state["narrator_style"],
          prompt_path: NARRATOR_PROMPT_PATH
        )

        # Step 7: Apply world-state diff from narration
        diff = narration["diff"] || {}
        world_state = Arena::WorldStateManager.new(world_state).apply_scene_diff(diff, presenter: presenter)

        # Step 8: Generate new scene if player moved to unknown location
        new_player_scene = world_state["player_scene"]
        generated_scenes = world_state["generated_scenes"] || {}
        if new_player_scene && !generated_scenes.key?(new_player_scene)
          world_state = generate_new_scene(game, world_state, player_scene, new_player_scene, diff)
        end

        world_state["act_turn"] = act_turn_number

        # Persist updated world state
        game.update!(world_state: world_state)

        # Step 9: Persist turn
        llm_memory = narration["memory_note"]
        narrative_content = narration["narrative"] || ""
        tokens_used = difficulty_tokens + narrator_tokens

        roll_payload = {
          "roll" => outcome[:roll],
          "difficulty" => difficulty,
          "momentum_at_roll" => momentum_at_roll,
          "health_loss" => outcome[:health_loss]
        }

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

        # Step 10: Check health depletion (only end condition in random mode)
        if world_state["health"].to_i <= 0
          epilogue_narration, epilogue_tokens = ArenaNarratorService.narrate_epilogue(
            scene_context, action, resolution_tag,
            "The hero has fallen. Their journey ends here.",
            world_context: world_state["world_context"],
            narrator_style: world_state["narrator_style"]
          )

          TurnPersistenceService.create!(
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
    end

    def self.generate_new_scene(game, world_state, origin_scene_id, target_scene_id, diff)
      generated_scenes = world_state["generated_scenes"] || {}

      # Find the exit label used
      origin_scene = generated_scenes[origin_scene_id]
      exit_used = (origin_scene&.dig("exits") || []).find { |e| e["to"] == target_scene_id }
      exit_label = exit_used&.dig("label") || target_scene_id.to_s.tr("_", " ")

      # Gather context
      presenter = RandomMode::WorldPresenter.new(world_state)
      inventory = presenter.send(:player_inventory, world_state)
      memory_notes = game.turns.where.not(llm_memory: [ nil, "" ]).order(:turn_number)
                         .map { |t| { turn_number: t.turn_number, note: t.llm_memory } }

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
