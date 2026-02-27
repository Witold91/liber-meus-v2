require "test_helper"

class ArenaFlows::StartScenarioFlowTest < ActiveSupport::TestCase
  setup do
    ScenarioCatalog.reload!
  end

  test "creates a game with hero, chapter, and intro turn" do
    assert_difference "Game.count", 1 do
      assert_difference "Chapter.count", 1 do
        assert_difference "Turn.count", 1 do
          @game = ArenaFlows::StartScenarioFlow.call(scenario_slug: "prison_break")
        end
      end
    end

    assert_equal "prison_break", @game.scenario_slug
    assert_equal "active", @game.status
    assert_equal "en", @game.game_language
  end

  test "creates hero from scenario definition if no hero_id" do
    initial_count = Hero.count
    @game = ArenaFlows::StartScenarioFlow.call(scenario_slug: "prison_break")
    assert Hero.count >= initial_count
    assert_equal "convict", @game.hero.slug
  end

  test "uses existing hero_id if provided" do
    hero = heroes(:convict)
    @game = ArenaFlows::StartScenarioFlow.call(scenario_slug: "prison_break", hero_id: hero.id)
    assert_equal hero.id, @game.hero_id
  end

  test "world_state contains required keys" do
    @game = ArenaFlows::StartScenarioFlow.call(scenario_slug: "prison_break")
    ws = @game.world_state
    assert ws.key?("health")
    assert ws.key?("danger_level")
    assert ws.key?("momentum")
    assert ws.key?("player_stage")
    assert ws.key?("actors")
    assert ws.key?("objects")
  end

  test "world_state player_stage set to first stage" do
    @game = ArenaFlows::StartScenarioFlow.call(scenario_slug: "prison_break")
    assert_equal "cell", @game.world_state["player_stage"]
  end

  test "intro turn has prologue flag" do
    @game = ArenaFlows::StartScenarioFlow.call(scenario_slug: "prison_break")
    intro = @game.turns.find_by(turn_number: 0)
    assert_not_nil intro
    assert intro.options_payload["prologue"]
  end

  test "raises for unknown scenario slug" do
    assert_raises(KeyError) do
      ArenaFlows::StartScenarioFlow.call(scenario_slug: "bogus")
    end
  end
end
