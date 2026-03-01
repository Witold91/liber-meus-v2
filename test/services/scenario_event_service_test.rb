require "test_helper"

class ScenarioEventServiceTest < ActiveSupport::TestCase
  setup do
    ScenarioCatalog.reload!
    @world_state = {
      "scenario_slug" => "prison_break",
      "act_number" => 1,
      "player_scene" => "cell",
      "actors" => {
        "guard_rodriguez" => { "scene" => "cell_block", "status" => "asleep" },
        "guard_chen" => { "scene" => "guard_room", "status" => "asleep" }
      }
    }
  end

  test "returns empty array when no events match turn" do
    events = ScenarioEventService.events_for_turn(turn_number: 1, world_state: @world_state)
    assert_equal [], events
  end

  test "returns events matching trigger_turn and condition" do
    events = ScenarioEventService.events_for_turn(turn_number: 5, world_state: @world_state)
    assert events.any?, "Should have rodriguez_wakes event at turn 5"
    assert events.any? { |e| e["id"] == "rodriguez_wakes" }
  end

  test "does not return event if condition not met" do
    state = @world_state.merge(
      "actors" => { "guard_rodriguez" => { "scene" => "cell_block", "status" => "awake" } }
    )
    events = ScenarioEventService.events_for_turn(turn_number: 5, world_state: state)
    refute events.any? { |e| e["id"] == "rodriguez_wakes" }
  end

  test "event_to_scene_diff returns actor_moved_to for actor_enters" do
    event = {
      "action" => {
        "type" => "actor_enters",
        "actor_id" => "guard_rodriguez",
        "scene" => "cell_block",
        "new_status" => "awake"
      }
    }
    diff = ScenarioEventService.event_to_scene_diff(event)
    assert_equal "cell_block", diff.dig("actor_moved_to", "guard_rodriguez")
    assert_equal "awake", diff.dig("actor_updates", "guard_rodriguez", "status")
  end

  test "event_to_scene_diff returns empty for world_flag type" do
    event = { "action" => { "type" => "world_flag", "flag" => "dawn_alarm", "value" => true } }
    diff = ScenarioEventService.event_to_scene_diff(event)
    assert_equal({}, diff)
  end

  test "returns empty array for unknown scenario slug" do
    state = @world_state.merge("scenario_slug" => "nonexistent")
    events = ScenarioEventService.events_for_turn(turn_number: 5, world_state: state)
    assert_equal [], events
  end

  test "supports act_turn triggers for multi-act scenarios" do
    state = {
      "scenario_slug" => "romeo_juliet",
      "act_number" => 1,
      "player_scene" => "verona_square",
      "actors" => {},
      "objects" => {}
    }

    events = ScenarioEventService.events_for_turn(turn_number: 99, act_turn_number: 3, world_state: state)
    assert events.any? { |e| e["id"] == "act1_brawl_escalates" }
  end

  test "state-triggered event fires when actor condition is met" do
    state = @world_state.merge(
      "actors" => {
        "guard_rodriguez" => { "scene" => "cell_block", "status" => "alerted" },
        "guard_chen" => { "scene" => "guard_room", "status" => "asleep" }
      }
    )
    events = ScenarioEventService.events_for_turn(turn_number: 99, world_state: state)
    assert events.any? { |e| e["id"] == "chen_alerted_by_rodriguez" }, "Should fire chen_alerted_by_rodriguez when rodriguez is alerted"
  end

  test "state-triggered event does not fire when actor condition is not met" do
    events = ScenarioEventService.events_for_turn(turn_number: 99, world_state: @world_state)
    refute events.any? { |e| e["id"] == "chen_alerted_by_rodriguez" }, "Should not fire when rodriguez is asleep"
  end

  test "state-triggered event does not fire if already in fired_events" do
    state = @world_state.merge(
      "actors" => {
        "guard_rodriguez" => { "scene" => "cell_block", "status" => "alerted" },
        "guard_chen" => { "scene" => "guard_room", "status" => "asleep" }
      },
      "fired_events" => [ "chen_alerted_by_rodriguez" ]
    )
    events = ScenarioEventService.events_for_turn(turn_number: 99, world_state: state)
    refute events.any? { |e| e["id"] == "chen_alerted_by_rodriguez" }, "Should not re-fire already-fired event"
  end

  test "object_status trigger fires when object condition is met" do
    state = @world_state.merge(
      "objects" => { "rope" => { "status" => "deployed" } }
    )
    events = ScenarioEventService.events_for_turn(turn_number: 99, world_state: state)
    assert events.any? { |e| e["id"] == "rope_noise_wakes_guard" }, "Should fire rope_noise_wakes_guard when rope is deployed"
  end

  test "object_status trigger does not fire when object condition is not met" do
    state = @world_state.merge(
      "objects" => { "rope" => { "status" => "made" } }
    )
    events = ScenarioEventService.events_for_turn(turn_number: 99, world_state: state)
    refute events.any? { |e| e["id"] == "rope_noise_wakes_guard" }, "Should not fire when rope is not deployed"
  end

  test "player_at_scene trigger fires when player is at the specified scene" do
    state = @world_state.merge("player_scene" => "guard_station")
    events = ScenarioEventService.events_for_turn(turn_number: 99, world_state: state)
    assert events.any? { |e| e["id"] == "rodriguez_spots_intruder" }, "Should fire when player enters guard_station"
  end

  test "player_at_scene trigger does not fire when player is elsewhere" do
    events = ScenarioEventService.events_for_turn(turn_number: 99, world_state: @world_state)
    refute events.any? { |e| e["id"] == "rodriguez_spots_intruder" }, "Should not fire when player is not at guard_station"
  end
end
