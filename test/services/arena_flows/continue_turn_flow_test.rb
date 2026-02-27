require "test_helper"

class ArenaFlows::ContinueTurnFlowTest < ActiveSupport::TestCase
  setup do
    ScenarioCatalog.reload!
    @game = games(:prison_game)
    @game.update!(world_state: {
      "health" => 100,
      "danger_level" => 40,
      "momentum" => 0,
      "arc_index" => 1,
      "scenario_slug" => "prison_break",
      "chapter_number" => 1,
      "player_stage" => "cell",
      "actors" => {
        "guard_rodriguez" => { "stage" => "cell_block", "status" => "awake" },
        "guard_chen" => { "stage" => "guard_room", "status" => "asleep" },
        "inmate_torres" => { "stage" => "cell", "status" => "sleeping" }
      },
      "objects" => {
        "loose_grate" => { "stage" => "cell", "status" => "in_place" },
        "guard_keys" => { "stage" => "guard_room", "status" => "on_belt" },
        "uniform" => { "stage" => "storage_room", "status" => "on_shelf" },
        "master_switch" => { "stage" => "control_room", "status" => "locked" },
        "rope" => { "stage" => "cell", "status" => "not_made" }
      }
    })

    # Stub AI calls
    DifficultyRatingService.stubs(:rate).returns([ { "difficulty" => "easy", "reasoning" => "No guards." }, 42 ])
    ArenaNarratorService.stubs(:narrate).returns([
      {
        "narrative" => "You carefully remove the grate.",
        "diff" => { "object_updates" => { "loose_grate" => { "status" => "removed" } } }
      },
      87
    ])
  end

  test "creates a new turn" do
    assert_difference "Turn.count", 1 do
      ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Remove the grate")
    end
  end

  test "turn has correct content and action" do
    turn = ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Remove the grate")
    assert_equal "You carefully remove the grate.", turn.content
    assert_equal "Remove the grate", turn.option_selected
  end

  test "turn has a resolution_tag" do
    turn = ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Remove the grate")
    assert_includes %w[success partial failure], turn.resolution_tag
  end

  test "applies world state diff from narration" do
    ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Remove the grate")
    @game.reload
    assert_equal "removed", @game.world_state.dig("objects", "loose_grate", "status")
  end

  test "increments turn_number" do
    turn = ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Remove the grate")
    assert_equal 1, turn.turn_number
  end

  test "persists summed token usage from both AI calls" do
    turn = ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Remove the grate")
    assert_equal 129, turn.tokens_used  # 42 (difficulty) + 87 (narrator)
  end

  test "raises when no active chapter" do
    chapters(:chapter_one).update!(status: "completed")
    assert_raises(RuntimeError) do
      ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Do something")
    end
  end

  test "raises AIConnectionError and creates no turn when first AI call fails" do
    DifficultyRatingService.stubs(:rate).raises(::AIConnectionError, "network error")

    assert_no_difference "Turn.count" do
      assert_raises(::AIConnectionError) do
        ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Remove the grate")
      end
    end
  end

  test "raises AIConnectionError and rolls back world state when second AI call fails" do
    ArenaNarratorService.stubs(:narrate).raises(::AIConnectionError, "network error")
    original_health = @game.world_state["health"]

    assert_no_difference "Turn.count" do
      assert_raises(::AIConnectionError) do
        ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Remove the grate")
      end
    end

    @game.reload
    assert_equal original_health, @game.world_state["health"]
  end
end
