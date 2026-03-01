require "test_helper"

class ArenaFlows::LoadSaveFlowTest < ActiveSupport::TestCase
  setup do
    @game = games(:prison_game)
    @user = users(:one)

    @saved_world_state = {
      "health" => 90,
      "danger_level" => 45,
      "momentum" => 1,
      "act_number" => 1,
      "act_turn" => 3,
      "scenario_slug" => "prison_break",
      "player_scene" => "cell",
      "actors" => {},
      "objects" => {},
      "improvised_objects" => {}
    }

    @save = Save.create!(
      game: @game,
      user: @user,
      hero: @game.hero,
      world_state: @saved_world_state,
      act_number: 1,
      turn_number: 3,
      label: "Act 1, Turn 3"
    )

    # Set up game with progress beyond the save point
    @game.update!(world_state: {
      "health" => 60,
      "danger_level" => 70,
      "momentum" => 2,
      "act_number" => 1,
      "act_turn" => 6,
      "scenario_slug" => "prison_break",
      "player_scene" => "guard_room",
      "actors" => {},
      "objects" => {},
      "improvised_objects" => {}
    })

    # Create extra turns after the save point
    @turn_after = Turn.create!(
      game: @game,
      act: acts(:act_one),
      content: "A later turn.",
      turn_number: 4,
      option_selected: "Do something"
    )
    @turn_after2 = Turn.create!(
      game: @game,
      act: acts(:act_one),
      content: "An even later turn.",
      turn_number: 5,
      option_selected: "Do another thing"
    )
  end

  test "restores game world state from save" do
    ArenaFlows::LoadSaveFlow.call(game: @game, save: @save)
    @game.reload

    assert_equal 90, @game.world_state["health"]
    assert_equal 45, @game.world_state["danger_level"]
    assert_equal 1, @game.world_state["momentum"]
    assert_equal "cell", @game.world_state["player_scene"]
  end

  test "restores hero from save" do
    ArenaFlows::LoadSaveFlow.call(game: @game, save: @save)
    @game.reload

    assert_equal @save.hero_id, @game.hero_id
  end

  test "sets game status to active" do
    @game.update!(status: "completed")

    ArenaFlows::LoadSaveFlow.call(game: @game, save: @save)
    @game.reload

    assert_equal "active", @game.status
  end

  test "deletes turns after save point" do
    ArenaFlows::LoadSaveFlow.call(game: @game, save: @save)

    assert_not Turn.exists?(@turn_after.id)
    assert_not Turn.exists?(@turn_after2.id)
  end

  test "keeps turns at and before save point" do
    intro = turns(:intro_turn)
    ArenaFlows::LoadSaveFlow.call(game: @game, save: @save)

    assert Turn.exists?(intro.id)
  end

  test "reactivates target act" do
    act = acts(:act_one)
    act.update!(status: "completed")

    ArenaFlows::LoadSaveFlow.call(game: @game, save: @save)
    act.reload

    assert_equal "active", act.status
  end

  test "deletes saves created after loaded save" do
    later_save = Save.create!(
      game: @game,
      user: @user,
      hero: @game.hero,
      world_state: @game.world_state,
      act_number: 1,
      turn_number: 5,
      label: "Act 1, Turn 5",
      created_at: @save.created_at + 1.hour
    )

    ArenaFlows::LoadSaveFlow.call(game: @game, save: @save)

    assert_not Save.exists?(later_save.id)
    assert Save.exists?(@save.id)
  end

  test "raises error if save does not belong to game" do
    other_game = Game.create!(
      hero: heroes(:convict),
      user: @user,
      scenario_slug: "prison_break",
      game_language: "en",
      status: "active",
      world_state: { "health" => 100 }
    )
    other_save = Save.create!(
      game: other_game,
      user: @user,
      hero: heroes(:convict),
      world_state: { "health" => 100 },
      act_number: 1,
      turn_number: 0,
      label: "Act 1, Turn 0"
    )

    assert_raises(ArgumentError) do
      ArenaFlows::LoadSaveFlow.call(game: @game, save: other_save)
    end
  end
end
