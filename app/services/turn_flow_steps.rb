module TurnFlowSteps
  def fetch_recent_actions(game)
    game.turns.recent(3).to_a.reverse
        .map { |t| { turn_number: t.turn_number, action: t.option_selected, resolution: t.resolution_tag } }
  end

  def fetch_memory_notes(game)
    game.turns.with_memory.order(:turn_number)
        .map { |t| { turn_number: t.turn_number, note: t.llm_memory } }
  end

  def rate_difficulty(action, scene_context, hero, recent_actions, **opts)
    DifficultyRatingService.rate(action, scene_context, hero, recent_actions, **opts)
  end

  def resolve_outcome(game, action, turn_number, rating)
    intent = {
      difficulty: rating["difficulty"],
      danger: rating["danger"] || "none",
      impact: rating["impact"] || "positive",
      stance: rating["stance"] || rating["exposure"] || "active",
      healing: rating["healing"] == true
    }
    OutcomeResolutionService.resolve(game, action, turn_number, intent)
  end

  def broadcast_roll(stream, outcome, difficulty, momentum)
    return unless stream&.dig(:on_roll)

    stream[:on_roll].call(
      roll: outcome[:roll],
      difficulty: difficulty,
      momentum: momentum,
      resolution_tag: outcome[:resolution_tag],
      health_loss: outcome[:health_loss],
      health_gain: outcome[:health_gain]
    )
  end

  def build_turn_context(presenter, game, recent_actions, rating_reasoning, previous_narrative_tail, established_facts)
    {
      world_state_delta: presenter.world_state_delta,
      memory_summary: game.memory_summary,
      memory_notes: fetch_memory_notes(game),
      recent_actions: recent_actions,
      rating_reasoning: rating_reasoning,
      previous_narrative_tail: previous_narrative_tail.presence,
      established_facts: established_facts
    }
  end

  def build_roll_payload(outcome, difficulty, momentum, rating)
    {
      "roll" => outcome[:roll],
      "difficulty" => difficulty,
      "momentum_at_roll" => momentum,
      "health_loss" => outcome[:health_loss],
      "damage_dice" => outcome[:damage_dice],
      "health_gain" => outcome[:health_gain],
      "healing_dice" => outcome[:healing_dice],
      "stance" => rating["stance"] || rating["exposure"] || "active"
    }
  end

  def deduct_user_tokens(game, turn_number_range)
    return unless game.user.present?

    all_tokens = game.turns.where(turn_number: turn_number_range).sum(:tokens_used)
    game.user.deduct_tokens!(all_tokens)
  end
end
