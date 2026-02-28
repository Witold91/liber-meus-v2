require "test_helper"

class Arena::WorldStateManagerTest < ActiveSupport::TestCase
  setup do
    ScenarioCatalog.reload!
    @scenario = ScenarioCatalog.find("prison_break")
    @world_state = {
      "chapter_number" => 1,
      "player_stage" => "cell",
      "actors" => {
        "guard_rodriguez" => { "stage" => "cell_block", "status" => "awake" },
        "guard_chen" => { "stage" => "guard_room", "status" => "asleep" }
      },
      "objects" => {
        "loose_grate" => { "stage" => "cell", "status" => "in_place" }
      }
    }
  end

  test "apply_stage_diff updates actor status" do
    diff = { "actor_updates" => { "guard_rodriguez" => { "status" => "alerted" } } }
    result = Arena::WorldStateManager.new(@world_state).apply_stage_diff(diff, scenario: @scenario)
    assert_equal "alerted", result.dig("actors", "guard_rodriguez", "status")
  end

  test "apply_stage_diff allows any status on a known actor" do
    diff = { "actor_updates" => { "guard_rodriguez" => { "status" => "unconscious" } } }
    result = Arena::WorldStateManager.new(@world_state).apply_stage_diff(diff, scenario: @scenario)
    assert_equal "unconscious", result.dig("actors", "guard_rodriguez", "status")
  end

  test "apply_stage_diff updates object status" do
    diff = { "object_updates" => { "loose_grate" => { "status" => "removed" } } }
    result = Arena::WorldStateManager.new(@world_state).apply_stage_diff(diff, scenario: @scenario)
    assert_equal "removed", result.dig("objects", "loose_grate", "status")
  end

  test "apply_stage_diff moves actor" do
    diff = { "actor_moved_to" => { "guard_rodriguez" => "guard_room" } }
    result = Arena::WorldStateManager.new(@world_state).apply_stage_diff(diff, scenario: @scenario)
    assert_equal "guard_room", result.dig("actors", "guard_rodriguez", "stage")
  end

  test "apply_stage_diff rejects invalid actor stage" do
    diff = { "actor_moved_to" => { "guard_rodriguez" => "mars" } }
    result = Arena::WorldStateManager.new(@world_state).apply_stage_diff(diff, scenario: @scenario)
    assert_equal "cell_block", result.dig("actors", "guard_rodriguez", "stage")
  end

  test "apply_stage_diff moves player" do
    diff = { "player_moved_to" => "vent_shaft" }
    result = Arena::WorldStateManager.new(@world_state).apply_stage_diff(diff, scenario: @scenario)
    assert_equal "vent_shaft", result["player_stage"]
  end

  test "apply_stage_diff rejects invalid player stage" do
    diff = { "player_moved_to" => "moon" }
    result = Arena::WorldStateManager.new(@world_state).apply_stage_diff(diff, scenario: @scenario)
    assert_equal "cell", result["player_stage"]
  end

  test "apply_stage_diff allows any status on a known object" do
    diff = { "object_updates" => { "loose_grate" => { "status" => "buried" } } }
    result = Arena::WorldStateManager.new(@world_state).apply_stage_diff(diff, scenario: @scenario)
    assert_equal "buried", result.dig("objects", "loose_grate", "status")
  end

  test "apply_stage_diff ignores unknown actors" do
    diff = { "actor_updates" => { "ghost_actor" => { "status" => "awake" } } }
    result = Arena::WorldStateManager.new(@world_state).apply_stage_diff(diff, scenario: @scenario)
    assert_nil result.dig("actors", "ghost_actor")
  end

  test "apply_stage_diff resolves localized slug ids to canonical ids" do
    scenario_pl = ScenarioCatalog.find("prison_break", locale: "pl")
    diff = {
      "actor_updates" => { "wiezien_torres" => { "status" => "awake" } },
      "object_updates" => { "poluzowana_kratka_wentylacyjna" => { "status" => "removed" } },
      "player_moved_to" => "szyb_wentylacyjny"
    }

    result = Arena::WorldStateManager.new(@world_state).apply_stage_diff(diff, scenario: scenario_pl)

    assert_equal "awake", result.dig("actors", "inmate_torres", "status")
    assert_equal "removed", result.dig("objects", "loose_grate", "status")
    assert_equal "vent_shaft", result["player_stage"]
  end

  test "apply_stage_diff does not mutate original world_state" do
    original = @world_state.dup
    diff = { "player_moved_to" => "vent_shaft" }
    Arena::WorldStateManager.new(@world_state).apply_stage_diff(diff, scenario: @scenario)
    assert_equal original["player_stage"], @world_state["player_stage"]
  end
end
