require "test_helper"

class ScenarioEventServiceTest < ActiveSupport::TestCase
  setup do
    ScenarioCatalog.reload!
    @world_state = {
      "scenario_slug" => "romeo_juliet",
      "act_number" => 1,
      "player_scene" => "verona_square",
      "actors" => {
        "sampson" => { "scene" => "verona_square", "status" => "taunting" },
        "capulet_servant" => { "scene" => "verona_square", "status" => "searching" }
      }
    }
  end

  test "returns empty array when no events match turn" do
    events = ScenarioEventService.events_for_turn(turn_number: 1, world_state: @world_state)
    assert_equal [], events
  end

  test "returns events matching act_turn trigger" do
    events = ScenarioEventService.events_for_turn(turn_number: 99, act_turn_number: 3, world_state: @world_state)
    assert events.any?, "Should have act1_brawl_escalates event at act_turn 3"
    assert events.any? { |e| e["id"] == "act1_brawl_escalates" }
  end

  test "does not return event if condition not met" do
    state = @world_state.merge(
      "actors" => { "capulet_servant" => { "scene" => "verona_square", "status" => "departed" } }
    )
    events = ScenarioEventService.events_for_turn(turn_number: 99, act_turn_number: 8, world_state: state)
    refute events.any? { |e| e["id"] == "act1_servant_returns" }
  end

  test "event_to_scene_diff returns actor_moved_to for actor_enters" do
    event = {
      "action" => {
        "type" => "actor_enters",
        "actor_id" => "tybalt",
        "scene" => "verona_square",
        "new_status" => "enraged"
      }
    }
    diff = ScenarioEventService.event_to_scene_diff(event)
    assert_equal "verona_square", diff.dig("actor_moved_to", "tybalt")
    assert_equal "enraged", diff.dig("actor_updates", "tybalt", "status")
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

  test "returns localized event descriptions when locale is provided" do
    state = {
      "scenario_slug" => "camillas_way_home",
      "act_number" => 1,
      "player_scene" => "bedroom_floor",
      "actors" => {},
      "objects" => {}
    }

    events = ScenarioEventService.events_for_turn(
      turn_number: 99,
      act_turn_number: 3,
      world_state: state,
      locale: "pl"
    )

    event = events.find { |e| e["id"] == "sisters_call" }
    assert_not_nil event
    assert_equal(
      "Alicia przyciska nosek do prętów klatki i piszczy głośno — długim, wysokim głosem, który niesie się echem po mieszkaniu. Woła Kamilę do domu.",
      event["description"]
    )
  end

  test "state-triggered event fires when actor condition is met" do
    state = {
      "scenario_slug" => "romeo_juliet",
      "act_number" => 3,
      "player_scene" => "dueling_square",
      "actors" => {
        "mercutio" => { "scene" => "dueling_square", "status" => "dead" },
        "tybalt" => { "scene" => "dueling_square", "status" => "dueling" }
      }
    }
    events = ScenarioEventService.events_for_turn(turn_number: 99, world_state: state)
    assert events.any? { |e| e["id"] == "act3_tybalt_turns_on_romeo" }, "Should fire act3_tybalt_turns_on_romeo when mercutio is dead"
  end

  test "state-triggered event does not fire when actor condition is not met" do
    state = {
      "scenario_slug" => "romeo_juliet",
      "act_number" => 3,
      "player_scene" => "dueling_square",
      "actors" => {
        "mercutio" => { "scene" => "dueling_square", "status" => "dueling" },
        "tybalt" => { "scene" => "dueling_square", "status" => "dueling" }
      }
    }
    events = ScenarioEventService.events_for_turn(turn_number: 99, world_state: state)
    refute events.any? { |e| e["id"] == "act3_tybalt_turns_on_romeo" }, "Should not fire when mercutio is not dead"
  end

  test "state-triggered event does not fire if already in fired_events" do
    state = {
      "scenario_slug" => "romeo_juliet",
      "act_number" => 3,
      "player_scene" => "dueling_square",
      "actors" => {
        "mercutio" => { "scene" => "dueling_square", "status" => "dead" },
        "tybalt" => { "scene" => "dueling_square", "status" => "dueling" }
      },
      "fired_events" => [ "act3_tybalt_turns_on_romeo" ]
    }
    events = ScenarioEventService.events_for_turn(turn_number: 99, world_state: state)
    refute events.any? { |e| e["id"] == "act3_tybalt_turns_on_romeo" }, "Should not re-fire already-fired event"
  end

  test "object_status trigger fires when object condition is met" do
    state = {
      "scenario_slug" => "romeo_juliet",
      "act_number" => 4,
      "player_scene" => "juliet_chamber",
      "actors" => {},
      "objects" => { "sleeping_draught" => { "status" => "taken" } }
    }
    events = ScenarioEventService.events_for_turn(turn_number: 99, world_state: state)
    assert events.any? { |e| e["id"] == "act4_plan_in_motion" }, "Should fire act4_plan_in_motion when sleeping_draught is taken"
  end

  test "object_status trigger does not fire when object condition is not met" do
    state = {
      "scenario_slug" => "romeo_juliet",
      "act_number" => 4,
      "player_scene" => "juliet_chamber",
      "actors" => {},
      "objects" => { "sleeping_draught" => { "status" => "prepared" } }
    }
    events = ScenarioEventService.events_for_turn(turn_number: 99, world_state: state)
    refute events.any? { |e| e["id"] == "act4_plan_in_motion" }, "Should not fire when sleeping_draught is not taken"
  end

  test "player_at_scene trigger fires when player is at the specified scene" do
    state = {
      "scenario_slug" => "romeo_juliet",
      "act_number" => 5,
      "player_scene" => "capulet_crypt",
      "actors" => {},
      "objects" => {}
    }
    events = ScenarioEventService.events_for_turn(turn_number: 99, world_state: state)
    assert events.any? { |e| e["id"] == "act5_romeo_enters_crypt" }, "Should fire when player enters capulet_crypt"
  end

  test "player_at_scene trigger does not fire when player is elsewhere" do
    state = {
      "scenario_slug" => "romeo_juliet",
      "act_number" => 5,
      "player_scene" => "mantua_street",
      "actors" => {},
      "objects" => {}
    }
    events = ScenarioEventService.events_for_turn(turn_number: 99, world_state: state)
    refute events.any? { |e| e["id"] == "act5_romeo_enters_crypt" }, "Should not fire when player is not at capulet_crypt"
  end
end
