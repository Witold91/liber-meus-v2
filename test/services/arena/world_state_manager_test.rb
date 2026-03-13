require "test_helper"

class Arena::WorldStateManagerTest < ActiveSupport::TestCase
  setup do
    ScenarioCatalog.reload!
    @scenario = ScenarioCatalog.find("romeo_juliet")
    @world_state = {
      "act_number" => 1,
      "player_scene" => "sycamore_grove",
      "actors" => {
        "sampson" => { "scene" => "verona_square", "status" => "taunting" },
        "benvolio" => { "scene" => "verona_square", "status" => "calm" }
      },
      "objects" => {
        "romeo_sword" => { "scene" => "player_inventory", "status" => "sheathed" }
      }
    }
  end

  test "apply_scene_diff updates actor status" do
    diff = { "actor_updates" => { "sampson" => { "status" => "brawling" } } }
    result = Arena::WorldStateManager.new(@world_state).apply_scene_diff(diff, scenario: @scenario)
    assert_equal "brawling", result.dig("actors", "sampson", "status")
  end

  test "apply_scene_diff allows any status on a known actor" do
    diff = { "actor_updates" => { "sampson" => { "status" => "unconscious" } } }
    result = Arena::WorldStateManager.new(@world_state).apply_scene_diff(diff, scenario: @scenario)
    assert_equal "unconscious", result.dig("actors", "sampson", "status")
  end

  test "apply_scene_diff updates object status" do
    diff = { "object_updates" => { "romeo_sword" => { "status" => "drawn" } } }
    result = Arena::WorldStateManager.new(@world_state).apply_scene_diff(diff, scenario: @scenario)
    assert_equal "drawn", result.dig("objects", "romeo_sword", "status")
  end

  test "apply_scene_diff moves actor" do
    diff = { "actor_moved_to" => { "sampson" => "montague_grounds" } }
    result = Arena::WorldStateManager.new(@world_state).apply_scene_diff(diff, scenario: @scenario)
    assert_equal "montague_grounds", result.dig("actors", "sampson", "scene")
  end

  test "apply_scene_diff rejects invalid actor scene" do
    diff = { "actor_moved_to" => { "sampson" => "mars" } }
    result = Arena::WorldStateManager.new(@world_state).apply_scene_diff(diff, scenario: @scenario)
    assert_equal "verona_square", result.dig("actors", "sampson", "scene")
  end

  test "apply_scene_diff moves player" do
    diff = { "player_moved_to" => "verona_square" }
    result = Arena::WorldStateManager.new(@world_state).apply_scene_diff(diff, scenario: @scenario)
    assert_equal "verona_square", result["player_scene"]
  end

  test "apply_scene_diff rejects invalid player scene" do
    diff = { "player_moved_to" => "moon" }
    result = Arena::WorldStateManager.new(@world_state).apply_scene_diff(diff, scenario: @scenario)
    assert_equal "sycamore_grove", result["player_scene"]
  end

  test "apply_scene_diff allows any status on a known object" do
    diff = { "object_updates" => { "romeo_sword" => { "status" => "broken" } } }
    result = Arena::WorldStateManager.new(@world_state).apply_scene_diff(diff, scenario: @scenario)
    assert_equal "broken", result.dig("objects", "romeo_sword", "status")
  end

  test "apply_scene_diff ignores unknown actors" do
    diff = { "actor_updates" => { "ghost_actor" => { "status" => "awake" } } }
    result = Arena::WorldStateManager.new(@world_state).apply_scene_diff(diff, scenario: @scenario)
    assert_nil result.dig("actors", "ghost_actor")
  end

  test "apply_scene_diff routes unknown object to improvised_objects" do
    diff = { "object_updates" => { "improvised_key" => { "status" => "in_hand" } } }
    result = Arena::WorldStateManager.new(@world_state).apply_scene_diff(diff, scenario: @scenario)
    assert_equal "in_hand", result.dig("improvised_objects", "improvised_key", "status")
  end

  test "apply_scene_diff stores scene for scene-bound improvised object" do
    diff = { "object_updates" => { "campfire" => { "status" => "burning", "scene" => "capulet_grounds" } } }
    result = Arena::WorldStateManager.new(@world_state).apply_scene_diff(diff, scenario: @scenario)
    assert_equal "burning", result.dig("improvised_objects", "campfire", "status")
    assert_equal "capulet_grounds", result.dig("improvised_objects", "campfire", "scene")
  end

  test "apply_scene_diff defaults improvised object status to acquired when no status given" do
    diff = { "object_updates" => { "torn_sheet_rope" => {} } }
    result = Arena::WorldStateManager.new(@world_state).apply_scene_diff(diff, scenario: @scenario)
    assert_equal "acquired", result.dig("improvised_objects", "torn_sheet_rope", "status")
  end

  test "apply_scene_diff works with localized scenario" do
    scenario_pl = ScenarioCatalog.find("romeo_juliet", locale: "pl")
    diff = {
      "actor_updates" => { "sampson" => { "status" => "brawling" } },
      "player_moved_to" => "verona_square"
    }

    result = Arena::WorldStateManager.new(@world_state).apply_scene_diff(diff, scenario: scenario_pl)

    assert_equal "brawling", result.dig("actors", "sampson", "status")
    assert_equal "verona_square", result["player_scene"]
  end

  test "apply_scene_diff registers new actor in random mode" do
    world_state = {
      "act_number" => 1,
      "player_scene" => "tavern",
      "actors" => {},
      "objects" => {},
      "generated_scenes" => {
        "tavern" => {
          "id" => "tavern", "name" => "Tavern", "description" => "A dusty tavern.",
          "exits" => [], "actors" => [], "objects" => []
        }
      }
    }
    presenter = RandomMode::WorldPresenter.new(world_state)

    diff = {
      "actor_updates" => {
        "old_bartender" => {
          "new_actor" => true,
          "name" => "Old Bartender",
          "description" => "A grizzled man polishing glasses.",
          "status" => "curious",
          "scene" => "tavern"
        }
      }
    }

    result = Arena::WorldStateManager.new(world_state).apply_scene_diff(diff, presenter: presenter)

    assert_equal "curious", result.dig("actors", "old_bartender", "status")
    assert_equal "tavern", result.dig("actors", "old_bartender", "scene")

    scene_actors = result.dig("generated_scenes", "tavern", "actors")
    assert scene_actors.any? { |a| a["id"] == "old_bartender" }
  end

  test "apply_scene_diff allows disposition update on new actor" do
    world_state = {
      "act_number" => 1,
      "player_scene" => "tavern",
      "actors" => {},
      "objects" => {},
      "generated_scenes" => {
        "tavern" => {
          "id" => "tavern", "name" => "Tavern", "description" => "A dusty tavern.",
          "exits" => [], "actors" => [], "objects" => []
        }
      }
    }
    presenter = RandomMode::WorldPresenter.new(world_state)

    diff = {
      "actor_updates" => {
        "old_bartender" => { "new_actor" => true, "name" => "Old Bartender", "status" => "curious", "scene" => "tavern" }
      },
      "disposition_updates" => { "old_bartender" => "friendly" }
    }

    result = Arena::WorldStateManager.new(world_state).apply_scene_diff(diff, presenter: presenter)

    assert_equal "friendly", result.dig("actors", "old_bartender", "disposition")
  end

  test "apply_scene_diff ignores unknown actors without new_actor flag" do
    original = @world_state.dup
    diff = { "player_moved_to" => "verona_square" }
    Arena::WorldStateManager.new(@world_state).apply_scene_diff(diff, scenario: @scenario)
    assert_equal original["player_scene"], @world_state["player_scene"]
  end
end
