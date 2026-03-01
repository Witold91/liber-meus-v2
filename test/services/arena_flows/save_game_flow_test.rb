require "test_helper"

class ArenaFlows::SaveGameFlowTest < ActiveSupport::TestCase
  setup do
    @game = games(:prison_game)
    @user = users(:one)
    @game.update!(world_state: {
      "health" => 85,
      "danger_level" => 50,
      "momentum" => 1,
      "act_number" => 1,
      "act_turn" => 4,
      "scenario_slug" => "prison_break",
      "player_scene" => "cell_block",
      "actors" => {},
      "objects" => {},
      "improvised_objects" => {}
    })
  end

  test "creates a save record" do
    assert_difference "Save.count", 1 do
      ArenaFlows::SaveGameFlow.call(game: @game, user: @user)
    end
  end

  test "save has correct attributes" do
    save = ArenaFlows::SaveGameFlow.call(game: @game, user: @user)

    assert_equal @game.id, save.game_id
    assert_equal @user.id, save.user_id
    assert_equal @game.hero_id, save.hero_id
    assert_equal 1, save.act_number
    assert_equal @game.turns.maximum(:turn_number), save.turn_number
    assert_equal "Act 1, Turn #{save.turn_number}", save.label
  end

  test "save captures full world state" do
    save = ArenaFlows::SaveGameFlow.call(game: @game, user: @user)

    assert_equal 85, save.world_state["health"]
    assert_equal 50, save.world_state["danger_level"]
    assert_equal "cell_block", save.world_state["player_scene"]
  end

  test "save is a deep copy of world state" do
    save = ArenaFlows::SaveGameFlow.call(game: @game, user: @user)

    @game.world_state["health"] = 0
    @game.save!

    save.reload
    assert_equal 85, save.world_state["health"]
  end
end
