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

  test "find returns the romeo_juliet scenario" do
    scenario = ScenarioCatalog.find("romeo_juliet")
    assert_not_nil scenario
    assert_equal "romeo_juliet", scenario["slug"]
    assert_equal "Romeo & Juliet", scenario["title"]
  end

  test "find returns nil for unknown slug" do
    assert_nil ScenarioCatalog.find("nonexistent_scenario")
  end

  test "find! returns scenario for known slug" do
    scenario = ScenarioCatalog.find!("romeo_juliet")
    assert_not_nil scenario
  end

  test "find! raises KeyError for unknown slug" do
    assert_raises(KeyError) { ScenarioCatalog.find!("bogus") }
  end

  test "reload! refreshes cache" do
    ScenarioCatalog.reload!
    assert ScenarioCatalog.all.any?
  end

  test "romeo_juliet scenario has required keys" do
    scenario = ScenarioCatalog.find("romeo_juliet")
    assert scenario.key?("slug")
    assert scenario.key?("title")
    assert scenario.key?("description")
    assert scenario.key?("turn_limit")
    assert scenario.key?("acts")
    assert scenario.key?("hero")
  end

  test "romeo_juliet act has scenes and actors" do
    scenario = ScenarioCatalog.find("romeo_juliet")
    act = scenario["acts"].first
    assert act["scenes"].any?
    assert act["actors"].any?
    assert act["objects"].any?
  end

  test "find with locale pl returns Polish title for romeo_juliet" do
    scenario = ScenarioCatalog.find("romeo_juliet", locale: "pl")
    assert_not_nil scenario
    assert_equal "Romeo i Julia", scenario["title"]
  end

  test "find with locale pl returns Polish title for camillas_way_home" do
    scenario = ScenarioCatalog.find("camillas_way_home", locale: "pl")
    assert_not_nil scenario
    assert_equal "Droga Kamili do domu", scenario["title"]
  end

  test "find with locale pl returns Polish title for korgoth_of_barbaria" do
    scenario = ScenarioCatalog.find("korgoth_of_barbaria", locale: "pl")
    assert_not_nil scenario
    assert_equal "Korgoth z Barbarii", scenario["title"]
  end

  test "find with locale pl merges scene name" do
    scenario = ScenarioCatalog.find("romeo_juliet", locale: "pl")
    act = scenario["acts"].first
    scene = act["scenes"].find { |s| s["id"] == "sycamore_grove" }
    assert_not_nil scene
    assert_equal "Gaj Jaworowy", scene["name"]
  end

  test "find with locale pl merges exit label" do
    scenario = ScenarioCatalog.find("romeo_juliet", locale: "pl")
    act = scenario["acts"].first
    scene = act["scenes"].find { |s| s["id"] == "sycamore_grove" }
    exit_to_verona = scene["exits"].find { |e| e["to"] == "verona_square" }
    assert_not_nil exit_to_verona
    assert_equal "Rusz do miasta", exit_to_verona["label"]
  end

  test "find with locale pl merges scene name for romeo_juliet verona_square" do
    scenario = ScenarioCatalog.find("romeo_juliet", locale: "pl")
    act = scenario["acts"].first
    scene = act["scenes"].find { |s| s["id"] == "verona_square" }
    assert_not_nil scene
    assert_equal "Plac w Weronie", scene["name"]
  end

  test "find with locale pl merges hero llm_description and event description" do
    scenario = ScenarioCatalog.find("camillas_way_home", locale: "pl")

    assert_equal(
      "Samica, mała biała myszka o ciemnych oczach. Domowa myszka mieszkająca w klatce z dwiema siostrami. Zwinna, ale niezdarna. Ciekawska, łagodnie odważna, łatwo płoszy się nowościami, lecz zawsze idzie dalej.",
      scenario.dig("hero", "llm_description")
    )

    event = scenario.dig("acts", 0, "events").find { |e| e["id"] == "sisters_call" }
    assert_equal(
      "Alicia przyciska nosek do prętów klatki i piszczy głośno — długim, wysokim głosem, który niesie się echem po mieszkaniu. Woła Kamilę do domu.",
      event["description"]
    )
  end

  test "find with locale pl merges korgoth hero scene and event description" do
    scenario = ScenarioCatalog.find("korgoth_of_barbaria", locale: "pl")

    assert_equal(
      "Mężczyzna, około trzydziestki. Olbrzymi barbarzyńca — ciężko pokryty bliznami, nadludzko silny, o suchym cynicznym humorze. Niechętny, ale druzgocąco skuteczny w walce. Mówi rzadko, uderza często.",
      scenario.dig("hero", "llm_description")
    )

    scene = scenario.dig("acts", 0, "scenes").find { |s| s["id"] == "holding_pens" }
    assert_equal "Kojce", scene["name"]

    event = scenario.dig("acts", 0, "events").find { |e| e["id"] == "act1_vexxa_taunts" }
    assert_equal(
      "Vexxa staje przy kratach. \"Nie bierz tego do siebie, Korgoth. Ojciec potrzebował świeżego mięsa, a ty byłeś najświeższą rzeczą, która piła samotnie.\" Uśmiecha się jak nóż.",
      event["description"]
    )
  end

  test "find with unsupported locale falls back to English" do
    scenario = ScenarioCatalog.find("romeo_juliet", locale: "de")
    assert_not_nil scenario
    assert_equal "Romeo & Juliet", scenario["title"]
  end

  test "find with locale en returns English base" do
    scenario = ScenarioCatalog.find("romeo_juliet", locale: "en")
    assert_not_nil scenario
    assert_equal "Romeo & Juliet", scenario["title"]
  end

  test "find with locale pl preserves structural fields from base" do
    scenario = ScenarioCatalog.find("romeo_juliet", locale: "pl")
    act = scenario["acts"].first
    scene = act["scenes"].find { |s| s["id"] == "sycamore_grove" }
    exit_to_montague = scene["exits"].find { |e| e["to"] == "montague_grounds" }
    assert_not_nil exit_to_montague
    actor = act["actors"].find { |a| a["id"] == "sampson" }
    assert_equal "taunting", actor["default_status"]
    assert_includes actor["status_options"], "brawling"
  end

  test "all returns only base scenarios without locale variants" do
    scenarios = ScenarioCatalog.all
    assert scenarios.all? { |s| s["slug"].present? }
    slugs = scenarios.map { |s| s["slug"] }
    assert_includes slugs, "camillas_way_home"
    assert_includes slugs, "korgoth_of_barbaria"
    assert_includes slugs, "romeo_juliet"
    assert_includes slugs, "tavern_heist"
  end
end
