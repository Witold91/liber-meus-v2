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

    events = ScenarioEventService.events_for_turn(turn_number: 99, act_turn_number: 1, world_state: state)
    assert events.any? { |e| e["id"] == "act1_opening_brawl" }
  end
end
