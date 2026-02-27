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

      # Step 4: Build stage context
      presenter = Arena::ScenarioPresenter.new(scenario, world_state["chapter_number"] || 1, world_state)
      player_stage = world_state["player_stage"] || presenter.stages.first&.dig("id")
      stage_context = presenter.stage_context_for(player_stage, world_state)

      # Step 5: Rate difficulty (AI call 1)
      rating, difficulty_tokens = DifficultyRatingService.rate(action, stage_context, game.hero)
      difficulty = rating["difficulty"]

      # Step 6: Resolve outcome (deterministic)
      intent = { difficulty: difficulty }
      outcome = OutcomeResolutionService.resolve(game, action, turn_number, intent)
      resolution_tag = outcome[:resolution_tag]

      # Reload world_state after outcome update
      game.reload
      world_state = game.world_state

      # Step 7: Get narration (AI call 2)
      recent_turns = game.turns.recent(5).to_a
      narration, narrator_tokens = ArenaNarratorService.narrate(action, resolution_tag, difficulty, stage_context, recent_turns)

      # Step 8: Apply world-state diff from narration
      diff = narration["diff"] || {}
      world_state = Arena::WorldStateManager.new(world_state).apply_stage_diff(diff, scenario: scenario)

      # Step 9: Apply scenario events
      ScenarioEventService.events_for_turn(turn_number: turn_number, world_state: world_state).each do |event|
        event_diff = ScenarioEventService.event_to_stage_diff(event)
        next if event_diff.empty?
        world_state = Arena::WorldStateManager.new(world_state).apply_stage_diff(event_diff, scenario: scenario)
      end

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

      # Check end conditions
      end_condition = EndConditionChecker.check(turn_number, world_state, scenario)
      if end_condition
        final_status = end_condition["type"] == "goal" ? "completed" : "failed"
        game.update!(status: final_status)
        chapter.update!(status: "completed")
      end

      turn
      end # transaction
    end
  end
end
