require "test_helper"

class ArenaFlows::ContinueTurnFlowTest < ActiveSupport::TestCase
  setup do
    ScenarioCatalog.reload!
    @game = games(:prison_game)
    @game.update!(world_state: {
      "health" => 100,
      "danger_level" => 40,
      "momentum" => 0,
      "act_number" => 1,
      "act_turn" => 0,
      "scenario_slug" => "prison_break",
      "player_scene" => "cell",
      "actors" => {
        "guard_rodriguez" => { "scene" => "cell_block", "status" => "awake" },
        "guard_chen" => { "scene" => "guard_room", "status" => "asleep" },
        "inmate_torres" => { "scene" => "cell", "status" => "sleeping" }
      },
      "objects" => {
        "loose_grate" => { "scene" => "cell", "status" => "in_place" },
        "guard_keys" => { "scene" => "guard_room", "status" => "on_belt" },
        "uniform" => { "scene" => "storage_room", "status" => "on_shelf" },
        "master_switch" => { "scene" => "control_room", "status" => "locked" },
        "rope" => { "scene" => "cell", "status" => "not_made" }
      },
      "improvised_objects" => {}
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
    ArenaNarratorService.stubs(:narrate_epilogue).returns([ { "narrative" => "The story reaches its conclusion." }, 55 ])
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

  test "creates ending sequence turn and marks game completed at goal" do
    @game.update!(world_state: @game.world_state.merge("player_scene" => "perimeter_wall"))
    ArenaNarratorService.stubs(:narrate).returns([
      {
        "narrative" => "You slip through the last opening.",
        "diff" => { "player_moved_to" => "freedom" }
      },
      87
    ])
    ArenaNarratorService.stubs(:narrate_epilogue).returns([ { "narrative" => "Freedom stretches out before you." }, 55 ])

    assert_difference "Turn.count", 2 do
      ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Climb over the wall")
    end

    @game.reload
    assert_equal "completed", @game.status

    ending_turn = @game.turns.order(:turn_number).last
    assert ending_turn.options_payload["ending"]
    assert_equal "completed", ending_turn.options_payload["ending_status"]
    assert_includes ending_turn.content, "Freedom stretches out before you."
  end

  test "advances to next act when act_goal condition is met" do
    two_act_scenario = {
      "slug" => "prison_break",
      "world_context" => "",
      "narrator_style" => "",
      "turn_limit" => 20,
      "acts" => [
        {
          "number" => 1,
          "intro" => "Act I intro",
          "scenes" => [ { "id" => "cell", "name" => "Cell", "description" => "", "exits" => [] } ],
          "actors" => [],
          "objects" => [],
          "conditions" => [],
          "events" => []
        },
        {
          "number" => 2,
          "intro" => "Act II intro",
          "scenes" => [ { "id" => "balcony", "name" => "Balcony", "description" => "", "exits" => [] } ],
          "actors" => [],
          "objects" => [],
          "conditions" => [],
          "events" => []
        }
      ]
    }

    ScenarioCatalog.stubs(:find!).returns(two_act_scenario)
    ScenarioCatalog.stubs(:find).returns(two_act_scenario)
    EndConditionChecker.stubs(:check).returns(
      {
        "id" => "act1_complete",
        "type" => "act_goal",
        "next_act" => 2,
        "narrative" => "Act I closes."
      }
    )

    ArenaNarratorService.stubs(:narrate_epilogue).returns([ { "narrative" => "The chapter draws to a close." }, 55 ])
    ArenaNarratorService.stubs(:narrate_prologue).returns([
      { "narrative" => "A new chapter begins.", "memory_note" => "Act II has started." },
      45
    ])

    assert_difference "Act.count", 1 do
      assert_difference "Turn.count", 3 do
        ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Advance the act")
      end
    end

    @game.reload
    assert_equal "active", @game.status
    assert_equal 2, @game.world_state["act_number"]
    assert_equal 0, @game.world_state["act_turn"]
    assert_equal "balcony", @game.world_state["player_scene"]
    assert_equal "completed", acts(:act_one).reload.status
    assert_equal 2, @game.current_act.number

    all_turns = @game.turns.order(:turn_number).to_a
    closing_turn = all_turns[-2]
    prologue_turn = all_turns[-1]

    assert closing_turn.options_payload["act_transition"]
    assert_equal 2, closing_turn.options_payload["next_act_number"]
    assert_includes closing_turn.content, "The chapter draws to a close."

    assert prologue_turn.options_payload["prologue"]
    assert_equal 2, prologue_turn.options_payload["act_number"]
    assert_equal "A new chapter begins.", prologue_turn.content
    assert_equal "Act II has started.", prologue_turn.llm_memory
  end

  test "creates ending sequence turn and marks game failed on danger condition" do
    ArenaNarratorService.stubs(:narrate).returns([
      {
        "narrative" => "A shadow crosses the bars.",
        "diff" => { "actor_updates" => { "guard_rodriguez" => { "status" => "alerted" } } }
      },
      87
    ])
    ArenaNarratorService.stubs(:narrate_epilogue).returns([ { "narrative" => "The cell closes around you once more." }, 55 ])

    assert_difference "Turn.count", 2 do
      ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Rattle the door loudly")
    end

    @game.reload
    assert_equal "failed", @game.status

    ending_turn = @game.turns.order(:turn_number).last
    assert ending_turn.options_payload["ending"]
    assert_equal "failed", ending_turn.options_payload["ending_status"]
    assert_includes ending_turn.content, "The cell closes around you once more."
  end

  test "raises when no active act" do
    acts(:act_one).update!(status: "completed")
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
