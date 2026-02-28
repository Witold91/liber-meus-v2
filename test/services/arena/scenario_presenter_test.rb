require "test_helper"

class Arena::ScenarioPresenterTest < ActiveSupport::TestCase
  setup do
    ScenarioCatalog.reload!
    @scenario = ScenarioCatalog.find("prison_break")
    @world_state = {
      "player_scene" => "cell",
      "actors" => {
        "guard_rodriguez" => { "scene" => "cell_block", "status" => "awake" },
        "guard_chen" => { "scene" => "guard_room", "status" => "asleep" }
      },
      "objects" => {
        "loose_grate" => { "scene" => "cell", "status" => "in_place" }
      }
    }
    @presenter = Arena::ScenarioPresenter.new(@scenario, 1, @world_state)
  end

  test "act returns act 1" do
    act = @presenter.act
    assert_not_nil act
    assert_equal 1, act["number"]
  end

  test "scenes returns array of scene hashes" do
    assert @presenter.scenes.any?
    assert @presenter.scenes.first.key?("id")
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

  test "scene_context_for returns context for cell" do
    ctx = @presenter.scene_context_for("cell", @world_state)
    assert_not_nil ctx
    assert_equal "cell", ctx.dig(:scene, :id)
    assert_equal "Your Cell", ctx.dig(:scene, :name)
  end

  test "scene_context_for includes actors at that scene" do
    ctx = @presenter.scene_context_for("cell_block", @world_state)
    actor_ids = ctx[:actors].map { |a| a[:id] }
    assert_includes actor_ids, "guard_rodriguez"
  end

  test "scene_context_for includes objects at that scene" do
    ctx = @presenter.scene_context_for("cell", @world_state)
    obj_ids = ctx[:objects].map { |o| o[:id] }
    assert_includes obj_ids, "loose_grate"
  end

  test "scene_context_for returns nil for unknown scene" do
    assert_nil @presenter.scene_context_for("bogus_scene", @world_state)
  end

  test "adjacent_scene_ids returns reachable scenes" do
    adj = @presenter.adjacent_scene_ids("cell")
    assert_includes adj, "cell_block"
    assert_includes adj, "vent_shaft"
  end

  test "exit_scene? returns false for cell" do
    refute @presenter.exit_scene?("cell")
  end

  test "exit_scene? returns true for perimeter_wall" do
    assert @presenter.exit_scene?("perimeter_wall")
  end
end
