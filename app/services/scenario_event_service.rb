class ScenarioEventService
  def self.events_for_turn(turn_number:, world_state:, act_turn_number: nil)
    scenario_slug = world_state["scenario_slug"]
    return [] unless scenario_slug

    scenario = ScenarioCatalog.find(scenario_slug)
    return [] unless scenario

    presenter = Arena::ScenarioPresenter.new(scenario, world_state["act_number"] || 1, world_state)

    presenter.events.select do |event|
      target_turn = if event.key?("act_turn")
        act_turn_number
      else
        turn_number
      end
      trigger = event["act_turn"] || event["trigger_turn"]

      next false unless trigger.to_i == target_turn.to_i
      condition_met?(event["condition"], world_state)
    end
  end

  def self.event_to_scene_diff(event)
    action = event["action"]
    return {} unless action

    case action["type"]
    when "actor_enters"
      diff = { "actor_moved_to" => { action["actor_id"] => action["scene"] } }
      if action["new_status"]
        diff["actor_updates"] = { action["actor_id"] => { "status" => action["new_status"] } }
      end
      diff
    when "world_flag"
      {}
    else
      {}
    end
  end

  private

  def self.condition_met?(condition, world_state)
    return true if condition.nil?

    if (actor_cond = condition["actor_status"])
      actor_state = world_state.dig("actors", actor_cond["id"])
      status = actor_state&.dig("status") || actor_state&.dig("statuses")&.first
      return status == actor_cond["status"]
    end

    true
  end
end
