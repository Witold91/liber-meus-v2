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
    assert scenario.key?("acts")
    assert scenario.key?("hero")
  end

  test "prison_break act has scenes and actors" do
    scenario = ScenarioCatalog.find("prison_break")
    act = scenario["acts"].first
    assert act["scenes"].any?
    assert act["actors"].any?
    assert act["objects"].any?
  end

  test "find with locale pl returns Polish title" do
    scenario = ScenarioCatalog.find("prison_break", locale: "pl")
    assert_not_nil scenario
    assert_equal "Ucieczka z Więzienia", scenario["title"]
  end

  test "find with locale pl returns Polish title for romeo_juliet" do
    scenario = ScenarioCatalog.find("romeo_juliet", locale: "pl")
    assert_not_nil scenario
    assert_equal "Romeo i Julia", scenario["title"]
  end

  test "find with locale pl merges scene name" do
    scenario = ScenarioCatalog.find("prison_break", locale: "pl")
    act = scenario["acts"].first
    cell_scene = act["scenes"].find { |s| s["id"] == "cell" }
    assert_not_nil cell_scene
    assert_equal "Twoja Cela", cell_scene["name"]
  end

  test "find with locale pl merges exit label" do
    scenario = ScenarioCatalog.find("prison_break", locale: "pl")
    act = scenario["acts"].first
    cell_scene = act["scenes"].find { |s| s["id"] == "cell" }
    exit_to_vent = cell_scene["exits"].find { |e| e["to"] == "vent_shaft" }
    assert_not_nil exit_to_vent
    assert_equal "Kratka wentylacyjna (nad pryczą)", exit_to_vent["label"]
  end

  test "find with locale pl merges scene name for romeo_juliet" do
    scenario = ScenarioCatalog.find("romeo_juliet", locale: "pl")
    act = scenario["acts"].first
    scene = act["scenes"].find { |s| s["id"] == "verona_square" }
    assert_not_nil scene
    assert_equal "Plac w Weronie (Akt I)", scene["name"]
  end

  test "find with unsupported locale falls back to English" do
    scenario = ScenarioCatalog.find("prison_break", locale: "de")
    assert_not_nil scenario
    assert_equal "Prison Break", scenario["title"]
  end

  test "find with locale en returns English base" do
    scenario = ScenarioCatalog.find("prison_break", locale: "en")
    assert_not_nil scenario
    assert_equal "Prison Break", scenario["title"]
  end

  test "find with locale pl preserves structural fields from base" do
    scenario = ScenarioCatalog.find("prison_break", locale: "pl")
    act = scenario["acts"].first
    cell_scene = act["scenes"].find { |s| s["id"] == "cell" }
    exit_to_cell_block = cell_scene["exits"].find { |e| e["to"] == "cell_block" }
    assert_equal true, exit_to_cell_block["locked"]
    actor = act["actors"].find { |a| a["id"] == "guard_rodriguez" }
    assert_equal "awake", actor["default_status"]
    assert_includes actor["status_options"], "alerted"
  end

  test "all returns only base scenarios without locale variants" do
    scenarios = ScenarioCatalog.all
    assert scenarios.all? { |s| s["slug"].present? }
    slugs = scenarios.map { |s| s["slug"] }
    assert_includes slugs, "prison_break"
    assert_includes slugs, "romeo_juliet"
    assert_includes slugs, "romeo_juliet_test"
  end
end
