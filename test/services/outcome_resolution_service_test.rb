require "test_helper"

class OutcomeResolutionServiceTest < ActiveSupport::TestCase
  setup do
    @game = games(:prison_game)
    @game.update!(world_state: OutcomeResolutionService.initial_state.merge("chapter_number" => 1))
  end

  # --- trivial / impossible ---

  test "trivial difficulty always succeeds without a roll" do
    outcome = OutcomeResolutionService.resolve(@game, "look around", 1, { difficulty: "trivial", impact: "positive" })
    assert_equal "success", outcome[:resolution_tag]
    assert_nil outcome[:roll]
  end

  test "impossible difficulty always fails without a roll" do
    outcome = OutcomeResolutionService.resolve(@game, "punch through steel wall", 1, { difficulty: "impossible", impact: "positive" })
    assert_equal "failure", outcome[:resolution_tag]
    assert_nil outcome[:roll]
  end

  test "trivial action deals no health loss" do
    outcome = OutcomeResolutionService.resolve(@game, "look around", 1, { difficulty: "trivial", impact: "positive" })
    assert_equal 0, outcome[:health_loss]
  end

  test "impossible action deals maximum health loss" do
    outcome = OutcomeResolutionService.resolve(@game, "punch through steel wall", 1, { difficulty: "impossible", impact: "positive" })
    assert_equal 30, outcome[:health_loss]
  end

  # --- impact on momentum ---

  test "positive impact: success gives +1 momentum" do
    OutcomeResolutionService.stubs(:rand).returns(6)
    OutcomeResolutionService.resolve(@game, "remove the grate", 1, { difficulty: "easy", impact: "positive" })
    @game.reload
    assert_equal 1, @game.world_state["momentum"]
  end

  test "none impact: success gives no momentum" do
    OutcomeResolutionService.stubs(:rand).returns(6)
    OutcomeResolutionService.resolve(@game, "eat the rose", 1, { difficulty: "easy", impact: "none" })
    @game.reload
    assert_equal 0, @game.world_state["momentum"]
  end

  test "none impact: failure gives only -1 momentum" do
    @game.update!(world_state: @game.world_state.merge("momentum" => 0))
    OutcomeResolutionService.stubs(:rand).returns(1)
    OutcomeResolutionService.resolve(@game, "eat the rose", 1, { difficulty: "medium", impact: "none" })
    @game.reload
    assert_equal(-1, @game.world_state["momentum"])
  end

  test "negative impact: success still costs momentum" do
    OutcomeResolutionService.stubs(:rand).returns(6)
    OutcomeResolutionService.resolve(@game, "alert the guard", 1, { difficulty: "easy", impact: "negative" })
    @game.reload
    assert_equal(-1, @game.world_state["momentum"])
  end

  test "major impact: success gives +2 momentum" do
    # roll 6 + momentum 0 = 6 > medium threshold 4 → success
    OutcomeResolutionService.stubs(:rand).returns(6)
    OutcomeResolutionService.resolve(@game, "unlock master control", 1, { difficulty: "medium", impact: "major" })
    @game.reload
    assert_equal 2, @game.world_state["momentum"]
  end

  test "major impact: partial gives +1 momentum" do
    # roll 4 + momentum 0 = 4 == medium threshold 4 → partial
    OutcomeResolutionService.stubs(:rand).returns(4)
    OutcomeResolutionService.resolve(@game, "unlock master control", 1, { difficulty: "medium", impact: "major" })
    @game.reload
    assert_equal 1, @game.world_state["momentum"]
  end

  # --- defaults ---

  test "impact defaults to positive when omitted" do
    OutcomeResolutionService.stubs(:rand).returns(6)
    outcome = OutcomeResolutionService.resolve(@game, "remove the grate", 1, { difficulty: "easy" })
    assert_equal "success", outcome[:resolution_tag]
    @game.reload
    assert_equal 1, @game.world_state["momentum"]
  end
end
