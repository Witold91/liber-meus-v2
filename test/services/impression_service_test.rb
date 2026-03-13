require "test_helper"

class ImpressionServiceTest < ActiveSupport::TestCase
  setup do
    ENV["OPENAI_API_KEY"] = "test-key-placeholder"
    @game = games(:romeo_game)
  end

  test "store! creates impressions from narration data" do
    impressions_data = [
      { "subject" => "guard_rodriguez", "type" => "actor", "fact" => "Rodriguez is suspicious" },
      { "subject" => "cell", "type" => "scene", "fact" => "The cell smells damp" }
    ]
    EmbeddingService.stubs(:embed).returns([[0.1] * 1536, [0.2] * 1536])

    assert_difference "Impression.count", 2 do
      ImpressionService.store!(game: @game, turn_number: 5, impressions_data: impressions_data)
    end

    imp = @game.impressions.where(subject_type: "actor").last
    assert_equal "guard_rodriguez", imp.subject_id
    assert_equal "Rodriguez is suspicious", imp.fact
    assert_equal 5, imp.turn_number
  end

  test "store! appends memory_note as memory-type impression" do
    EmbeddingService.stubs(:embed).returns([[0.3] * 1536])

    assert_difference "Impression.count", 1 do
      ImpressionService.store!(game: @game, turn_number: 3, impressions_data: [], memory_note: "Player befriended the guard")
    end

    imp = @game.impressions.where(subject_type: "memory").last
    assert_equal "Player befriended the guard", imp.fact
    assert_nil imp.subject_id
  end

  test "store! handles nil impressions_data gracefully" do
    assert_nothing_raised do
      ImpressionService.store!(game: @game, turn_number: 1, impressions_data: nil)
    end
  end

  test "store! skips entries without fact" do
    impressions_data = [
      { "subject" => "guard", "type" => "actor", "fact" => "" },
      { "subject" => "cell", "type" => "scene", "fact" => "Valid fact" }
    ]
    EmbeddingService.stubs(:embed).returns([[0.1] * 1536])

    assert_difference "Impression.count", 1 do
      ImpressionService.store!(game: @game, turn_number: 1, impressions_data: impressions_data)
    end
  end

  test "store! is non-fatal when embedding fails" do
    EmbeddingService.stubs(:embed).raises(StandardError, "API down")

    assert_nothing_raised do
      ImpressionService.store!(
        game: @game, turn_number: 1,
        impressions_data: [{ "subject" => "cell", "type" => "scene", "fact" => "test" }]
      )
    end
  end

  test "retrieve returns facts for matching scene and actor ids" do
    EmbeddingService.stubs(:embed_single).returns([0.1] * 1536)

    facts = ImpressionService.retrieve(
      game: @game, scene_id: "cell",
      actor_ids: ["guard_rodriguez"],
      action_text: "look around"
    )

    assert facts.is_a?(Array)
    assert facts.all? { |f| f.is_a?(String) }
  end

  test "retrieve returns empty array on failure" do
    EmbeddingService.stubs(:embed_single).raises(StandardError, "API down")

    facts = ImpressionService.retrieve(
      game: @game, scene_id: "cell",
      actor_ids: ["guard_rodriguez"],
      action_text: "look around"
    )

    assert_equal [], facts
  end

  test "retrieve excludes memory-type impressions" do
    EmbeddingService.stubs(:embed).returns([[0.1] * 1536])
    ImpressionService.store!(game: @game, turn_number: 1, impressions_data: [], memory_note: "Secret memory")

    EmbeddingService.stubs(:embed_single).returns([0.1] * 1536)

    facts = ImpressionService.retrieve(
      game: @game, scene_id: "nonexistent",
      actor_ids: [],
      action_text: "Secret memory"
    )

    refute facts.include?("Secret memory")
  end
end
