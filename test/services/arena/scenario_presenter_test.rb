require "test_helper"

class Arena::ScenarioPresenterTest < ActiveSupport::TestCase
  setup do
    ScenarioCatalog.reload!
    @scenario = ScenarioCatalog.find("prison_break")
    @world_state = {
      "player_stage" => "cell",
      "actors" => {
        "guard_rodriguez" => { "stage" => "cell_block", "status" => "awake" },
        "guard_chen" => { "stage" => "guard_room", "status" => "asleep" }
      },
      "objects" => {
        "loose_grate" => { "stage" => "cell", "status" => "in_place" }
      }
    }
    @presenter = Arena::ScenarioPresenter.new(@scenario, 1, @world_state)
  end

  test "chapter returns chapter 1" do
    chapter = @presenter.chapter
    assert_not_nil chapter
    assert_equal 1, chapter["number"]
  end

  test "stages returns array of stage hashes" do
    assert @presenter.stages.any?
    assert @presenter.stages.first.key?("id")
  end

  test "actors returns array" do
    assert @presenter.actors.any?
  end

  test "objects returns array" do
    assert @presenter.objects.any?
  end

  test "turn_limit returns integer" do
    assert_equal 20, @presenter.turn_limit
  end

  test "stage_context_for returns context for cell" do
    ctx = @presenter.stage_context_for("cell", @world_state)
    assert_not_nil ctx
    assert_equal "cell", ctx.dig(:stage, :id)
    assert_equal "Your Cell", ctx.dig(:stage, :name)
  end

  test "stage_context_for includes actors at that stage" do
    ctx = @presenter.stage_context_for("cell_block", @world_state)
    actor_ids = ctx[:actors].map { |a| a[:id] }
    assert_includes actor_ids, "guard_rodriguez"
  end

  test "stage_context_for includes objects at that stage" do
    ctx = @presenter.stage_context_for("cell", @world_state)
    obj_ids = ctx[:objects].map { |o| o[:id] }
    assert_includes obj_ids, "loose_grate"
  end

  test "stage_context_for returns nil for unknown stage" do
    assert_nil @presenter.stage_context_for("bogus_stage", @world_state)
  end

  test "adjacent_stage_ids returns reachable stages" do
    adj = @presenter.adjacent_stage_ids("cell")
    assert_includes adj, "cell_block"
    assert_includes adj, "vent_shaft"
  end

  test "exit_stage? returns false for cell" do
    refute @presenter.exit_stage?("cell")
  end

  test "exit_stage? returns true for perimeter_wall" do
    assert @presenter.exit_stage?("perimeter_wall")
  end
end
