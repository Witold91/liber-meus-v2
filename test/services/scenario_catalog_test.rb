require "test_helper"

class ScenarioCatalogTest < ActiveSupport::TestCase
  setup do
    ScenarioCatalog.reload!
  end

  test "all returns array of scenario hashes" do
    scenarios = ScenarioCatalog.all
    assert_kind_of Array, scenarios
    assert scenarios.any?, "Should have at least one scenario"
  end

  test "find returns the prison_break scenario" do
    scenario = ScenarioCatalog.find("prison_break")
    assert_not_nil scenario
    assert_equal "prison_break", scenario["slug"]
    assert_equal "Prison Break", scenario["title"]
  end

  test "find returns nil for unknown slug" do
    assert_nil ScenarioCatalog.find("nonexistent_scenario")
  end

  test "find! returns scenario for known slug" do
    scenario = ScenarioCatalog.find!("prison_break")
    assert_not_nil scenario
  end

  test "find! raises KeyError for unknown slug" do
    assert_raises(KeyError) { ScenarioCatalog.find!("bogus") }
  end

  test "reload! refreshes cache" do
    ScenarioCatalog.reload!
    assert ScenarioCatalog.all.any?
  end

  test "prison_break scenario has required keys" do
    scenario = ScenarioCatalog.find("prison_break")
    assert scenario.key?("slug")
    assert scenario.key?("title")
    assert scenario.key?("description")
    assert scenario.key?("turn_limit")
    assert scenario.key?("chapters")
    assert scenario.key?("hero")
  end

  test "prison_break chapter has stages and actors" do
    scenario = ScenarioCatalog.find("prison_break")
    chapter = scenario["chapters"].first
    assert chapter["stages"].any?
    assert chapter["actors"].any?
    assert chapter["objects"].any?
  end
end
