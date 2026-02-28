class EndConditionChecker
  def self.check(turn_number, world_state, scenario)
    presenter = Arena::ScenarioPresenter.new(scenario, world_state["chapter_number"] || 1, world_state)
    turn_limit = presenter.turn_limit

    # Auto condition: turn limit reached
    if turn_number >= turn_limit
      return {
        "id" => "turn_limit_reached",
        "type" => "failure",
        "narrative" => I18n.t("services.end_condition_checker.turn_limit_reached")
      }
    end

    # Health depletion
    if world_state["health"].to_i <= 0
      return {
        "id" => "health_depleted",
        "type" => "failure",
        "narrative" => I18n.t("services.end_condition_checker.health_depleted")
      }
    end

    # Goal conditions from scenario
    presenter.conditions.each do |condition|
      result = evaluate_condition(condition, world_state)
      return condition if result
    end

    nil
  end

  private

  def self.evaluate_condition(condition, world_state)
    case condition["check"]
    when "player_at_stage"
      world_state["player_stage"] == condition["stage"]
    when "actor_has_status"
      actor_state = world_state.dig("actors", condition["actor"])
      status = actor_state&.dig("status") || actor_state&.dig("statuses")&.first
      status == condition["status"]
    when "all_actors_have_status"
      (condition["actors"] || []).all? do |actor_id|
        actor_state = world_state.dig("actors", actor_id)
        status = actor_state&.dig("status") || actor_state&.dig("statuses")&.first
        status == condition["status"]
      end
    else
      false
    end
  end
end
