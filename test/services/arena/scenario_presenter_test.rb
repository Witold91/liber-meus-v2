require "test_helper"

class Arena::ScenarioPresenterTest < ActiveSupport::TestCase
  setup do
    ScenarioCatalog.reload!
    @scenario = ScenarioCatalog.find("romeo_juliet")
    @world_state = {
      "player_scene" => "sycamore_grove",
      "actors" => {
        "sampson" => { "scene" => "verona_square", "status" => "taunting" },
        "benvolio" => { "scene" => "verona_square", "status" => "calm" }
      },
      "objects" => {
        "romeo_sword" => { "scene" => "player_inventory", "status" => "sheathed" },
        "capulet_guest_list" => { "scene" => "verona_square", "status" => "servant_carried" }
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
    assert_equal 999, @presenter.turn_limit
  end

  test "scene_context_for returns context for sycamore_grove" do
    ctx = @presenter.scene_context_for("sycamore_grove", @world_state)
    assert_not_nil ctx
    assert_equal "sycamore_grove", ctx.dig(:scene, :id)
    assert_equal "Sycamore Grove", ctx.dig(:scene, :name)
  end

  test "scene_context_for includes actors at that scene" do
    ctx = @presenter.scene_context_for("verona_square", @world_state)
    actor_ids = ctx[:actors].map { |a| a[:id] }
    assert_includes actor_ids, "sampson"
  end

  test "scene_context_for includes objects at that scene" do
    ctx = @presenter.scene_context_for("verona_square", @world_state)
    obj_ids = ctx[:objects].map { |o| o[:id] }
    assert_includes obj_ids, "capulet_guest_list"
  end

  test "scene_context_for returns nil for unknown scene" do
    assert_nil @presenter.scene_context_for("bogus_scene", @world_state)
  end
end
