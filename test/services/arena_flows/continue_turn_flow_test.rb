require "test_helper"

class ArenaFlows::ContinueTurnFlowTest < ActiveSupport::TestCase
  setup do
    ScenarioCatalog.reload!
    @game = games(:romeo_game)
    @game.update!(world_state: {
      "health" => 100,
      "momentum" => 0,
      "act_number" => 1,
      "act_turn" => 0,
      "scenario_slug" => "romeo_juliet",
      "player_scene" => "sycamore_grove",
      "actors" => {
        "sampson" => { "scene" => "verona_square", "status" => "taunting" },
        "benvolio" => { "scene" => "verona_square", "status" => "calm" },
        "juliet" => { "scene" => "capulet_hall", "status" => "sheltered" }
      },
      "objects" => {
        "romeo_sword" => { "scene" => "player_inventory", "status" => "sheathed" },
        "capulet_guest_list" => { "scene" => "verona_square", "status" => "servant_carried" },
        "masquerade_mask" => { "scene" => "capulet_hall", "status" => "unused" }
      },
      "improvised_objects" => {}
    })

    # Stub AI calls and impression service
    ImpressionService.stubs(:retrieve).returns([])
    ImpressionService.stubs(:store!)
    DifficultyRatingService.stubs(:rate).returns([ { "difficulty" => "easy", "reasoning" => "No guards." }, 42 ])
    ArenaNarratorService.stubs(:narrate).returns([
      {
        "narrative" => "You draw your sword cautiously.",
        "diff" => { "object_updates" => { "romeo_sword" => { "status" => "drawn" } } }
      },
      87
    ])
    ArenaNarratorService.stubs(:narrate_epilogue).returns([ { "narrative" => "The story reaches its conclusion." }, 55 ])
  end

  test "creates a new turn" do
    assert_difference "Turn.count", 1 do
      ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Draw sword")
    end
  end

  test "turn has correct content and action" do
    turn = ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Draw sword")
    assert_equal "You draw your sword cautiously.", turn.content
    assert_equal "Draw sword", turn.option_selected
  end

  test "turn has a resolution_tag" do
    turn = ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Draw sword")
    assert_includes %w[success partial failure], turn.resolution_tag
  end

  test "applies world state diff from narration" do
    ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Draw sword")
    @game.reload
    assert_equal "drawn", @game.world_state.dig("objects", "romeo_sword", "status")
  end

  test "increments turn_number" do
    turn = ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Draw sword")
    assert_equal 1, turn.turn_number
  end

  test "persists summed token usage from both AI calls" do
    turn = ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Draw sword")
    assert_equal 129, turn.tokens_used  # 42 (difficulty) + 87 (narrator)
  end

  test "creates ending sequence turn and marks game completed at goal" do
    EndConditionChecker.stubs(:check).returns(
      { "id" => "goal_reached", "type" => "goal", "narrative" => "The lovers reunite." }
    )
    ArenaNarratorService.stubs(:narrate_epilogue).returns([ { "narrative" => "Freedom stretches out before you." }, 55 ])

    assert_difference "Turn.count", 2 do
      ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Reach the goal")
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
      "slug" => "romeo_juliet",
      "world_context" => "",
      "narrator_style" => "",
      "turn_limit" => 20,
      "acts" => [
        {
          "number" => 1,
          "intro" => "Act I intro",
          "scenes" => [ { "id" => "sycamore_grove", "name" => "Sycamore Grove", "description" => "", "exits" => [] } ],
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
    EndConditionChecker.stubs(:check).returns(
      { "id" => "danger_hit", "type" => "danger", "narrative" => "The danger strikes." }
    )
    ArenaNarratorService.stubs(:narrate_epilogue).returns([ { "narrative" => "The tragedy closes around you." }, 55 ])

    assert_difference "Turn.count", 2 do
      ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Rattle the door loudly")
    end

    @game.reload
    assert_equal "failed", @game.status

    ending_turn = @game.turns.order(:turn_number).last
    assert ending_turn.options_payload["ending"]
    assert_equal "failed", ending_turn.options_payload["ending_status"]
    assert_includes ending_turn.content, "The tragedy closes around you."
  end

  test "raises when no active act" do
    acts(:act_one).update!(status: "completed")
    assert_raises(RuntimeError) do
      ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Do something")
    end
  end

  test "carries actor statuses across act transitions" do
    two_act_scenario = {
      "slug" => "romeo_juliet",
      "world_context" => "",
      "narrator_style" => "",
      "turn_limit" => 20,
      "acts" => [
        {
          "number" => 1,
          "intro" => "Act I",
          "scenes" => [ { "id" => "sycamore_grove", "name" => "Sycamore Grove", "description" => "", "exits" => [] } ],
          "actors" => [
            { "id" => "npc_a", "name" => "NPC A", "scene" => "sycamore_grove", "default_status" => "alive", "status_options" => %w[alive dead] }
          ],
          "objects" => [
            { "id" => "obj_x", "name" => "Object X", "scene" => "sycamore_grove", "default_status" => "intact", "status_options" => %w[intact broken] }
          ],
          "conditions" => [],
          "events" => []
        },
        {
          "number" => 2,
          "intro" => "Act II",
          "scenes" => [ { "id" => "yard", "name" => "Yard", "description" => "", "exits" => [] } ],
          "actors" => [
            { "id" => "npc_a", "name" => "NPC A", "scene" => "yard", "default_status" => "alive", "status_options" => %w[alive dead] },
            { "id" => "npc_b", "name" => "NPC B", "scene" => "yard", "default_status" => "calm", "status_options" => %w[calm angry] }
          ],
          "objects" => [
            { "id" => "obj_x", "name" => "Object X", "scene" => "yard", "default_status" => "intact", "status_options" => %w[intact broken] }
          ],
          "conditions" => [],
          "events" => []
        }
      ]
    }

    # NPC A was killed and Object X was broken in Act 1
    @game.update!(world_state: @game.world_state.merge(
      "actors" => { "npc_a" => { "scene" => "sycamore_grove", "status" => "dead" } },
      "objects" => { "obj_x" => { "scene" => "sycamore_grove", "status" => "broken" } }
    ))

    ScenarioCatalog.stubs(:find!).returns(two_act_scenario)
    ScenarioCatalog.stubs(:find).returns(two_act_scenario)
    EndConditionChecker.stubs(:check).returns(
      { "id" => "act1_done", "type" => "act_goal", "next_act" => 2, "narrative" => "Act I closes." }
    )
    ArenaNarratorService.stubs(:narrate_epilogue).returns([ { "narrative" => "End of act." }, 55 ])
    ArenaNarratorService.stubs(:narrate_prologue).returns([ { "narrative" => "New act begins.", "memory_note" => "" }, 45 ])

    ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Advance")

    @game.reload
    # Actor status should carry over from Act 1
    assert_equal "dead", @game.world_state.dig("actors", "npc_a", "status"),
      "Actor status should carry across act transitions"
    # New actor should get its default
    assert_equal "calm", @game.world_state.dig("actors", "npc_b", "status"),
      "New actor should get default_status"
    # Object status should carry over too
    assert_equal "broken", @game.world_state.dig("objects", "obj_x", "status"),
      "Object status should carry across act transitions"
    # Scene should be from the new act's definition
    assert_equal "yard", @game.world_state.dig("actors", "npc_a", "scene"),
      "Actor scene should come from the new act's definition"
  end

  test "carries actor status through an act where the actor is absent" do
    three_act_scenario = {
      "slug" => "romeo_juliet",
      "world_context" => "",
      "narrator_style" => "",
      "turn_limit" => 20,
      "acts" => [
        {
          "number" => 1,
          "intro" => "Act I",
          "scenes" => [ { "id" => "sycamore_grove", "name" => "Sycamore Grove", "description" => "", "exits" => [] } ],
          "actors" => [
            { "id" => "npc_a", "name" => "NPC A", "scene" => "sycamore_grove", "default_status" => "alive", "status_options" => %w[alive dead] }
          ],
          "objects" => [],
          "conditions" => [],
          "events" => []
        },
        {
          "number" => 2,
          "intro" => "Act II — NPC A is not present here",
          "scenes" => [ { "id" => "yard", "name" => "Yard", "description" => "", "exits" => [] } ],
          "actors" => [
            { "id" => "npc_b", "name" => "NPC B", "scene" => "yard", "default_status" => "calm", "status_options" => %w[calm angry] }
          ],
          "objects" => [],
          "conditions" => [],
          "events" => []
        },
        {
          "number" => 3,
          "intro" => "Act III — NPC A returns",
          "scenes" => [ { "id" => "square", "name" => "Square", "description" => "", "exits" => [] } ],
          "actors" => [
            { "id" => "npc_a", "name" => "NPC A", "scene" => "square", "default_status" => "alive", "status_options" => %w[alive dead] }
          ],
          "objects" => [],
          "conditions" => [],
          "events" => []
        }
      ]
    }

    # NPC A was killed in Act 1
    @game.update!(world_state: @game.world_state.merge(
      "actors" => { "npc_a" => { "scene" => "sycamore_grove", "status" => "dead" } }
    ))

    ScenarioCatalog.stubs(:find!).returns(three_act_scenario)
    ScenarioCatalog.stubs(:find).returns(three_act_scenario)

    # Transition Act 1 → Act 2 (npc_a is NOT in Act 2)
    EndConditionChecker.stubs(:check).returns(
      { "id" => "act1_done", "type" => "act_goal", "next_act" => 2, "narrative" => "Act I closes." }
    )
    ArenaNarratorService.stubs(:narrate_epilogue).returns([ { "narrative" => "End." }, 55 ])
    ArenaNarratorService.stubs(:narrate_prologue).returns([ { "narrative" => "New act.", "memory_note" => "" }, 45 ])

    ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Advance to Act 2")
    @game.reload

    # npc_a should still be in world state even though Act 2 doesn't define him
    assert_equal "dead", @game.world_state.dig("actors", "npc_a", "status"),
      "Actor status should survive transition to an act where the actor is absent"

    # Now transition Act 2 → Act 3 (npc_a returns)
    EndConditionChecker.stubs(:check).returns(
      { "id" => "act2_done", "type" => "act_goal", "next_act" => 3, "narrative" => "Act II closes." }
    )

    ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Advance to Act 3")
    @game.reload

    assert_equal "dead", @game.world_state.dig("actors", "npc_a", "status"),
      "Actor status should carry from Act 1 through Act 2 (absent) to Act 3"
    assert_equal "square", @game.world_state.dig("actors", "npc_a", "scene"),
      "Actor scene should come from Act 3's definition"
  end

  test "force_status overrides carried-over status" do
    two_act_scenario = {
      "slug" => "romeo_juliet",
      "world_context" => "",
      "narrator_style" => "",
      "turn_limit" => 20,
      "acts" => [
        {
          "number" => 1,
          "intro" => "Act I",
          "scenes" => [ { "id" => "sycamore_grove", "name" => "Sycamore Grove", "description" => "", "exits" => [] } ],
          "actors" => [
            { "id" => "npc_a", "name" => "NPC A", "scene" => "sycamore_grove", "default_status" => "calm", "status_options" => %w[calm hostile friendly] }
          ],
          "objects" => [
            { "id" => "obj_x", "name" => "Object X", "scene" => "sycamore_grove", "default_status" => "intact", "status_options" => %w[intact broken repaired] }
          ],
          "conditions" => [],
          "events" => []
        },
        {
          "number" => 2,
          "intro" => "Act II",
          "scenes" => [ { "id" => "yard", "name" => "Yard", "description" => "", "exits" => [] } ],
          "actors" => [
            { "id" => "npc_a", "name" => "NPC A", "scene" => "yard", "default_status" => "calm", "force_status" => "hostile", "status_options" => %w[calm hostile friendly] },
            { "id" => "npc_b", "name" => "NPC B", "scene" => "yard", "default_status" => "calm", "force_status" => "friendly", "status_options" => %w[calm friendly] }
          ],
          "objects" => [
            { "id" => "obj_x", "name" => "Object X", "scene" => "yard", "default_status" => "intact", "force_status" => "repaired", "status_options" => %w[intact broken repaired] }
          ],
          "conditions" => [],
          "events" => []
        }
      ]
    }

    # NPC A became friendly and Object X was broken in Act 1
    @game.update!(world_state: @game.world_state.merge(
      "actors" => { "npc_a" => { "scene" => "sycamore_grove", "status" => "friendly" } },
      "objects" => { "obj_x" => { "scene" => "sycamore_grove", "status" => "broken" } }
    ))

    ScenarioCatalog.stubs(:find!).returns(two_act_scenario)
    ScenarioCatalog.stubs(:find).returns(two_act_scenario)
    EndConditionChecker.stubs(:check).returns(
      { "id" => "act1_done", "type" => "act_goal", "next_act" => 2, "narrative" => "Act I closes." }
    )
    ArenaNarratorService.stubs(:narrate_epilogue).returns([ { "narrative" => "End of act." }, 55 ])
    ArenaNarratorService.stubs(:narrate_prologue).returns([ { "narrative" => "New act begins.", "memory_note" => "" }, 45 ])

    ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Advance")

    @game.reload
    # force_status should override the carried-over "friendly"
    assert_equal "hostile", @game.world_state.dig("actors", "npc_a", "status"),
      "force_status should override carried-over status"
    # force_status should work for new actors too (overrides default_status)
    assert_equal "friendly", @game.world_state.dig("actors", "npc_b", "status"),
      "force_status should override default_status for new actors"
    # force_status should work for objects too
    assert_equal "repaired", @game.world_state.dig("objects", "obj_x", "status"),
      "force_status should override carried-over object status"
  end

  test "raises AIConnectionError and creates no turn when first AI call fails" do
    DifficultyRatingService.stubs(:rate).raises(::AIConnectionError, "network error")

    assert_no_difference "Turn.count" do
      assert_raises(::AIConnectionError) do
        ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Draw sword")
      end
    end
  end

  test "raises AIConnectionError and rolls back world state when second AI call fails" do
    ArenaNarratorService.stubs(:narrate).raises(::AIConnectionError, "network error")
    original_health = @game.world_state["health"]

    assert_no_difference "Turn.count" do
      assert_raises(::AIConnectionError) do
        ArenaFlows::ContinueTurnFlow.call(game: @game, action: "Draw sword")
      end
    end

    @game.reload
    assert_equal original_health, @game.world_state["health"]
  end
end
