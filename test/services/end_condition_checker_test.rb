require "test_helper"

class EndConditionCheckerTest < ActiveSupport::TestCase
  setup do
    ScenarioCatalog.reload!
    @scenario = ScenarioCatalog.find("prison_break")
    @world_state = {
      "chapter_number" => 1,
      "health" => 100,
      "player_stage" => "cell",
      "actors" => {},
      "objects" => {}
    }
  end

  test "returns nil when no conditions met and within turn limit" do
    result = EndConditionChecker.check(5, @world_state, @scenario)
    assert_nil result
  end

  test "returns failure condition when turn limit reached" do
    result = EndConditionChecker.check(20, @world_state, @scenario)
    assert_not_nil result
    assert_equal "turn_limit_reached", result["id"]
  end

  test "returns failure when turn exceeds limit" do
    result = EndConditionChecker.check(25, @world_state, @scenario)
    assert_not_nil result
  end

  test "returns failure when health is zero" do
    state = @world_state.merge("health" => 0)
    result = EndConditionChecker.check(5, state, @scenario)
    assert_not_nil result
    assert_equal "health_depleted", result["id"]
  end

  test "returns goal condition when player at exit stage" do
    state = @world_state.merge("player_stage" => "freedom")
    result = EndConditionChecker.check(5, state, @scenario)
    assert_not_nil result
    assert_equal "player_at_exit", result["id"]
  end
end
