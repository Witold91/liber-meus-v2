require "test_helper"

class OutcomeResolutionServiceTest < ActiveSupport::TestCase
  setup do
    @game = games(:prison_game)
    @game.update!(world_state: OutcomeResolutionService.initial_state.merge("chapter_number" => 1))
  end

  test "irrelevant action cannot succeed — best outcome is partial" do
    # Roll 6, easy threshold 1: 6 > 1 would normally be success
    OutcomeResolutionService.stubs(:rand).returns(6)
    outcome = OutcomeResolutionService.resolve(@game, "eat the rose", 1, { difficulty: "easy", relevant: false })
    assert_equal "partial", outcome[:resolution_tag]
  end

  test "irrelevant action can still fail on a bad roll" do
    # momentum -3, roll 1: total -2 < threshold 1 → failure even for irrelevant action
    @game.update!(world_state: @game.world_state.merge("momentum" => -3))
    OutcomeResolutionService.stubs(:rand).returns(1)
    outcome = OutcomeResolutionService.resolve(@game, "eat the rose", 1, { difficulty: "easy", relevant: false })
    assert_equal "failure", outcome[:resolution_tag]
  end

  test "relevant action can fully succeed" do
    OutcomeResolutionService.stubs(:rand).returns(6)
    outcome = OutcomeResolutionService.resolve(@game, "remove the grate", 1, { difficulty: "easy", relevant: true })
    assert_equal "success", outcome[:resolution_tag]
  end

  test "relevant defaults to true when omitted" do
    OutcomeResolutionService.stubs(:rand).returns(6)
    outcome = OutcomeResolutionService.resolve(@game, "remove the grate", 1, { difficulty: "easy" })
    assert_equal "success", outcome[:resolution_tag]
  end

  test "irrelevant success gives no momentum gain" do
    initial_momentum = @game.world_state["momentum"]
    OutcomeResolutionService.stubs(:rand).returns(6)
    OutcomeResolutionService.resolve(@game, "eat the rose", 1, { difficulty: "easy", relevant: false })
    @game.reload
    assert_equal initial_momentum, @game.world_state["momentum"]
  end
end
