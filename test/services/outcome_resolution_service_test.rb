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

  test "danger low: failure rolls 2d6 for health loss" do
    OutcomeResolutionService.stubs(:rand).returns(1)
    outcome = OutcomeResolutionService.resolve(@game, "climb the fence", 1, { difficulty: "medium", danger: "low", impact: "positive" })
    assert_equal [ 1, 1 ], outcome[:damage_dice]
    assert_equal 2, outcome[:health_loss]
  end

  test "danger medium: partial rolls 2d6 for health loss" do
    # roll 4 + momentum 0 = 4 == medium threshold → partial
    OutcomeResolutionService.stubs(:rand).returns(4)
    outcome = OutcomeResolutionService.resolve(@game, "fight the guard", 1, { difficulty: "medium", danger: "medium", impact: "positive" })
    assert_equal "partial", outcome[:resolution_tag]
    assert_equal [ 4, 4 ], outcome[:damage_dice]
    assert_equal 8, outcome[:health_loss]
  end

  test "danger high: failure rolls 8d6 for health loss" do
    OutcomeResolutionService.stubs(:rand).returns(3)
    outcome = OutcomeResolutionService.resolve(@game, "fight an armed guard", 1, { difficulty: "hard", danger: "high", impact: "positive" })
    assert_equal 8, outcome[:damage_dice].size
    assert_equal 24, outcome[:health_loss]
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

  test "healing true: success rolls 4d6 for health gain" do
    @game.update!(world_state: @game.world_state.merge("health" => 60))
    OutcomeResolutionService.stubs(:rand).returns(5)
    outcome = OutcomeResolutionService.resolve(@game, "bandage the wound", 1, { difficulty: "easy", danger: "none", healing: true })
    assert_equal [ 5, 5, 5, 5 ], outcome[:healing_dice]
    assert_equal 20, outcome[:health_gain]
    @game.reload
    assert_equal 80, @game.world_state["health"]
  end

  test "healing true: partial rolls 2d6 for health gain" do
    @game.update!(world_state: @game.world_state.merge("health" => 60))
    OutcomeResolutionService.stubs(:rand).returns(4)
    outcome = OutcomeResolutionService.resolve(@game, "bandage the wound", 1, { difficulty: "medium", danger: "none", healing: true })
    assert_equal "partial", outcome[:resolution_tag]
    assert_equal [ 4, 4 ], outcome[:healing_dice]
    assert_equal 8, outcome[:health_gain]
    @game.reload
    assert_equal 68, @game.world_state["health"]
  end

  test "healing true: failure restores nothing" do
    @game.update!(world_state: @game.world_state.merge("health" => 60))
    OutcomeResolutionService.stubs(:rand).returns(1)
    outcome = OutcomeResolutionService.resolve(@game, "perform surgery", 1, { difficulty: "hard", danger: "high", healing: true })
    assert_equal 0, outcome[:health_gain]
    assert_equal [], outcome[:healing_dice]
    @game.reload
    # 8d6 with all 1s = 8 damage; 60 - 8 + 0 = 52
    assert_equal 52, @game.world_state["health"]
  end

  test "healing cannot exceed max health" do
    @game.update!(world_state: @game.world_state.merge("health" => 95))
    OutcomeResolutionService.stubs(:rand).returns(6)
    outcome = OutcomeResolutionService.resolve(@game, "bandage the wound", 1, { difficulty: "easy", danger: "none", healing: true })
    # 4d6 with all 6s = 24, but capped at 100
    assert_equal 24, outcome[:health_gain]
    @game.reload
    assert_equal 100, @game.world_state["health"]
  end

  test "healing and danger stack on same turn" do
    @game.update!(world_state: @game.world_state.merge("health" => 60))
    # partial with high danger: 4d6 damage + 2d6 healing, all 4s
    OutcomeResolutionService.stubs(:rand).returns(4)
    outcome = OutcomeResolutionService.resolve(@game, "risky surgery", 1, { difficulty: "medium", danger: "high", healing: true })
    assert_equal "partial", outcome[:resolution_tag]
    assert_equal 16, outcome[:health_loss]
    assert_equal 8, outcome[:health_gain]
    @game.reload
    assert_equal 52, @game.world_state["health"]  # 60 - 16 + 8
  end

  test "healing false returns zero health_gain" do
    OutcomeResolutionService.stubs(:rand).returns(6)
    outcome = OutcomeResolutionService.resolve(@game, "look around", 1, { difficulty: "easy", danger: "none", healing: false })
    assert_equal 0, outcome[:health_gain]
  end

  # --- stance ---

  test "stance safe: no health loss even with high danger and failure" do
    OutcomeResolutionService.stubs(:rand).returns(1)
    outcome = OutcomeResolutionService.resolve(@game, "sing a song", 1, { difficulty: "hard", danger: "high", stance: "safe", impact: "positive" })
    assert_equal "failure", outcome[:resolution_tag]
    assert_equal 0, outcome[:health_loss]
  end

  test "stance exposed: rolls failure-level dice regardless of resolution" do
    OutcomeResolutionService.stubs(:rand).returns(3)
    outcome = OutcomeResolutionService.resolve(@game, "I wait", 1, { difficulty: "trivial", danger: "high", stance: "exposed", impact: "none" })
    assert_equal "success", outcome[:resolution_tag]
    assert_equal 8, outcome[:damage_dice].size  # 8d6 (high/failure)
    assert_equal 24, outcome[:health_loss]
  end

  test "stance exposed with medium danger" do
    OutcomeResolutionService.stubs(:rand).returns(3)
    outcome = OutcomeResolutionService.resolve(@game, "sing a song", 1, { difficulty: "trivial", danger: "medium", stance: "exposed", impact: "none" })
    assert_equal 4, outcome[:damage_dice].size  # 4d6 (medium/failure)
    assert_equal 12, outcome[:health_loss]
  end

  test "stance exposed with low danger" do
    OutcomeResolutionService.stubs(:rand).returns(3)
    outcome = OutcomeResolutionService.resolve(@game, "I wait", 1, { difficulty: "trivial", danger: "low", stance: "exposed", impact: "none" })
    assert_equal 2, outcome[:damage_dice].size  # 2d6 (low/failure)
    assert_equal 6, outcome[:health_loss]
  end

  test "stance exposed with danger none deals no damage" do
    outcome = OutcomeResolutionService.resolve(@game, "I wait", 1, { difficulty: "trivial", danger: "none", stance: "exposed", impact: "none" })
    assert_equal 0, outcome[:health_loss]
  end

  test "stance active uses resolution-based dice logic" do
    OutcomeResolutionService.stubs(:rand).returns(6)
    outcome = OutcomeResolutionService.resolve(@game, "dodge the beast", 1, { difficulty: "medium", danger: "high", stance: "active", impact: "positive" })
    assert_equal "success", outcome[:resolution_tag]
    assert_equal 0, outcome[:health_loss]
  end

  test "stance defaults to active when omitted" do
    OutcomeResolutionService.stubs(:rand).returns(6)
    outcome = OutcomeResolutionService.resolve(@game, "fight the guard", 1, { difficulty: "easy", danger: "high" })
    assert_equal "success", outcome[:resolution_tag]
    assert_equal 0, outcome[:health_loss]
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
