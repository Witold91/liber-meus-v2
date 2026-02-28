module ArenaFlows
  class ContinueTurnFlow
    def self.call(game:, action:)
      ActiveRecord::Base.transaction do
        # Step 1: Load scenario
        scenario = ScenarioCatalog.find!(game.scenario_slug, locale: game.game_language)
        world_state = game.world_state

        # Step 2: Determine turn number
        turn_number = (game.turns.maximum(:turn_number) || 0) + 1

        # Step 3: Get current chapter
        chapter = game.current_chapter
        raise I18n.t("services.arena_flows.continue_turn.no_active_chapter") unless chapter
        chapter_number = world_state["chapter_number"] || chapter.number || 1
        chapter_turn_number = world_state["chapter_turn"].to_i + 1

        # Step 4: Build stage context
        presenter = Arena::ScenarioPresenter.new(scenario, chapter_number, world_state)
        player_stage = world_state["player_stage"] || presenter.stages.first&.dig("id")
        stage_context = presenter.stage_context_for(player_stage, world_state)

        # Step 5: Rate difficulty (AI call 1)
        recent_actions = game.turns.recent(3).to_a.reverse
                             .map { |t| { turn_number: t.turn_number, action: t.option_selected, resolution: t.resolution_tag } }
        rating, difficulty_tokens = DifficultyRatingService.rate(action, stage_context, game.hero, recent_actions, world_context: scenario["world_context"])
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
        narration, narrator_tokens = ArenaNarratorService.narrate(action, resolution_tag, difficulty, stage_context, turn_context, outcome[:health_loss], world_context: scenario["world_context"], narrator_style: scenario["narrator_style"])

        # Step 8: Apply world-state diff from narration
        diff = narration["diff"] || {}
        world_state = Arena::WorldStateManager.new(world_state).apply_stage_diff(diff, scenario: scenario)

        # Step 9: Apply scenario events
        ScenarioEventService.events_for_turn(turn_number: turn_number, chapter_turn_number: chapter_turn_number, world_state: world_state).each do |event|
          event_diff = ScenarioEventService.event_to_stage_diff(event)
          next if event_diff.empty?
          world_state = Arena::WorldStateManager.new(world_state).apply_stage_diff(event_diff, scenario: scenario)
        end
        world_state["chapter_turn"] = chapter_turn_number

        # Persist updated world state
        game.update!(world_state: world_state)

        # Step 10: Persist turn
        llm_memory = narration["memory_note"]
        narrative_content = narration["narrative"] || ""
        tokens_used = difficulty_tokens + narrator_tokens

        turn = TurnPersistenceService.create!(
          game: game,
          chapter: chapter,
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
          if transition_to_next_chapter?(end_condition: end_condition, scenario: scenario, chapter_number: chapter_number)
            next_chapter_number = resolve_next_chapter_number(end_condition: end_condition, chapter_number: chapter_number)
            advance_chapter!(game: game, scenario: scenario, world_state: world_state, current_chapter: chapter, next_chapter_number: next_chapter_number)
            transition_turn_content = build_transition_turn_content(end_condition: end_condition, scenario: scenario, next_chapter_number: next_chapter_number)

            TurnPersistenceService.create!(
              game: game,
              chapter: chapter,
              content: transition_turn_content,
              turn_number: turn_number + 1,
              options_payload: {
                "ending" => true,
                "ending_status" => "completed",
                "ending_condition_id" => end_condition["id"],
                "chapter_transition" => true,
                "next_chapter_number" => next_chapter_number
              }
            )
          else
            final_status = %w[goal chapter_goal].include?(end_condition["type"]) ? "completed" : "failed"
            ending_turn_content = build_ending_turn_content(end_condition: end_condition)

            TurnPersistenceService.create!(
              game: game,
              chapter: chapter,
              content: ending_turn_content,
              turn_number: turn_number + 1,
              options_payload: {
                "ending" => true,
                "ending_status" => final_status,
                "ending_condition_id" => end_condition["id"]
              }
            )

            game.update!(status: final_status)
            chapter.update!(status: "completed")
          end
        end

        turn
      end # transaction
    end

    def self.build_ending_turn_content(end_condition:)
      end_condition["narrative"].to_s.strip
    end

    def self.build_transition_turn_content(end_condition:, scenario:, next_chapter_number:)
      next_intro = scenario["chapters"]&.find { |c| c["number"] == next_chapter_number }&.dig("intro")
      [ end_condition["narrative"].to_s.strip, next_intro.to_s.strip ].reject(&:blank?).join("\n\n")
    end

    def self.transition_to_next_chapter?(end_condition:, scenario:, chapter_number:)
      return false unless end_condition["type"] == "chapter_goal"
      next_chapter_number = resolve_next_chapter_number(end_condition: end_condition, chapter_number: chapter_number)
      scenario["chapters"].to_a.any? { |c| c["number"] == next_chapter_number }
    end

    def self.resolve_next_chapter_number(end_condition:, chapter_number:)
      (end_condition["next_chapter"] || (chapter_number.to_i + 1)).to_i
    end

    def self.advance_chapter!(game:, scenario:, world_state:, current_chapter:, next_chapter_number:)
      current_chapter.update!(status: "completed")

      next_chapter = game.chapters.find_or_create_by!(number: next_chapter_number) do |ch|
        ch.status = "active"
      end
      next_chapter.update!(status: "active")

      next_world_state = build_world_state_for_chapter(world_state: world_state, scenario: scenario, chapter_number: next_chapter_number)
      game.update!(world_state: next_world_state)
    end

    def self.build_world_state_for_chapter(world_state:, scenario:, chapter_number:)
      presenter = Arena::ScenarioPresenter.new(scenario, chapter_number, world_state)
      actors = presenter.actors.each_with_object({}) do |actor, h|
        h[actor["id"]] = { "stage" => actor["stage"], "status" => actor["default_status"] }
      end
      objects = presenter.objects.each_with_object({}) do |object, h|
        h[object["id"]] = { "stage" => object["stage"], "status" => object["default_status"] }
      end

      state = world_state.deep_dup
      state["chapter_number"] = chapter_number
      state["chapter_turn"] = 0
      state["player_stage"] = presenter.stages.first&.dig("id")
      state["actors"] = actors
      state["objects"] = objects
      state
    end

    private_class_method :build_ending_turn_content, :build_transition_turn_content, :transition_to_next_chapter?,
      :resolve_next_chapter_number, :advance_chapter!, :build_world_state_for_chapter
  end
end
