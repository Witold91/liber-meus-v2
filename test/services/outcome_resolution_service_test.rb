require "test_helper"

class OutcomeResolutionServiceTest < ActiveSupport::TestCase
  setup do
    @game = games(:romeo_game)
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

  test "danger none: no health loss even on failure" do
    OutcomeResolutionService.stubs(:rand).returns(1)
    outcome = OutcomeResolutionService.resolve(@game, "pick a lock alone", 1, { difficulty: "hard", danger: "none", impact: "positive" })
    assert_equal "failure", outcome[:resolution_tag]
    assert_equal 0, outcome[:health_loss]
  end

  test "danger low: failure deals 8 health loss" do
    OutcomeResolutionService.stubs(:rand).returns(1)
    outcome = OutcomeResolutionService.resolve(@game, "climb the fence", 1, { difficulty: "medium", danger: "low", impact: "positive" })
    assert_equal 8, outcome[:health_loss]
  end

  test "danger medium: partial deals 5 health loss" do
    # roll 4 + momentum 0 = 4 == medium threshold → partial
    OutcomeResolutionService.stubs(:rand).returns(4)
    outcome = OutcomeResolutionService.resolve(@game, "fight the guard", 1, { difficulty: "medium", danger: "medium", impact: "positive" })
    assert_equal "partial", outcome[:resolution_tag]
    assert_equal 5, outcome[:health_loss]
  end

  test "danger high: failure deals 35 health loss" do
    OutcomeResolutionService.stubs(:rand).returns(1)
    outcome = OutcomeResolutionService.resolve(@game, "fight an armed guard", 1, { difficulty: "hard", danger: "high", impact: "positive" })
    assert_equal 35, outcome[:health_loss]
  end

  test "success never deals health loss regardless of danger" do
    OutcomeResolutionService.stubs(:rand).returns(6)
    outcome = OutcomeResolutionService.resolve(@game, "fight an armed guard", 1, { difficulty: "easy", danger: "high", impact: "positive" })
    assert_equal "success", outcome[:resolution_tag]
    assert_equal 0, outcome[:health_loss]
  end

  test "danger defaults to none when omitted" do
    OutcomeResolutionService.stubs(:rand).returns(1)
    outcome = OutcomeResolutionService.resolve(@game, "pick a lock", 1, { difficulty: "hard" })
    assert_equal 0, outcome[:health_loss]
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

  test "none impact: failure leaves momentum unchanged" do
    @game.update!(world_state: @game.world_state.merge("momentum" => 0))
    OutcomeResolutionService.stubs(:rand).returns(1)
    OutcomeResolutionService.resolve(@game, "eat the rose", 1, { difficulty: "medium", impact: "none" })
    @game.reload
    assert_equal 0, @game.world_state["momentum"]
  end

  test "positive impact: failure costs -1 momentum" do
    OutcomeResolutionService.stubs(:rand).returns(1)
    OutcomeResolutionService.resolve(@game, "climb the wall", 1, { difficulty: "hard", impact: "positive" })
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

  # --- healing ---

  test "healing true: success restores 15 health" do
    @game.update!(world_state: @game.world_state.merge("health" => 60))
    OutcomeResolutionService.stubs(:rand).returns(6)
    outcome = OutcomeResolutionService.resolve(@game, "bandage the wound", 1, { difficulty: "easy", danger: "none", healing: true })
    assert_equal 15, outcome[:health_gain]
    @game.reload
    assert_equal 75, @game.world_state["health"]
  end

  test "healing true: partial restores 8 health" do
    @game.update!(world_state: @game.world_state.merge("health" => 60))
    OutcomeResolutionService.stubs(:rand).returns(4)
    outcome = OutcomeResolutionService.resolve(@game, "bandage the wound", 1, { difficulty: "medium", danger: "none", healing: true })
    assert_equal "partial", outcome[:resolution_tag]
    assert_equal 8, outcome[:health_gain]
    @game.reload
    assert_equal 68, @game.world_state["health"]
  end

  test "healing true: failure restores nothing" do
    @game.update!(world_state: @game.world_state.merge("health" => 60))
    OutcomeResolutionService.stubs(:rand).returns(1)
    outcome = OutcomeResolutionService.resolve(@game, "perform surgery", 1, { difficulty: "hard", danger: "high", healing: true })
    assert_equal 0, outcome[:health_gain]
    @game.reload
    assert_equal 25, @game.world_state["health"]  # 60 - 35 + 0
  end

  test "healing cannot exceed max health" do
    @game.update!(world_state: @game.world_state.merge("health" => 95))
    OutcomeResolutionService.stubs(:rand).returns(6)
    outcome = OutcomeResolutionService.resolve(@game, "bandage the wound", 1, { difficulty: "easy", danger: "none", healing: true })
    assert_equal 15, outcome[:health_gain]
    @game.reload
    assert_equal 100, @game.world_state["health"]
  end

  test "healing and danger stack on same turn" do
    @game.update!(world_state: @game.world_state.merge("health" => 60))
    # partial with high danger: -12 health, +8 healing = net -4
    OutcomeResolutionService.stubs(:rand).returns(4)
    outcome = OutcomeResolutionService.resolve(@game, "risky surgery", 1, { difficulty: "medium", danger: "high", healing: true })
    assert_equal "partial", outcome[:resolution_tag]
    assert_equal 12, outcome[:health_loss]
    assert_equal 8, outcome[:health_gain]
    @game.reload
    assert_equal 56, @game.world_state["health"]  # 60 - 12 + 8
  end

  test "healing false returns zero health_gain" do
    OutcomeResolutionService.stubs(:rand).returns(6)
    outcome = OutcomeResolutionService.resolve(@game, "look around", 1, { difficulty: "easy", danger: "none", healing: false })
    assert_equal 0, outcome[:health_gain]
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
