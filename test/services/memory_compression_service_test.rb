require "test_helper"

class MemoryCompressionServiceTest < ActiveSupport::TestCase
  setup do
    ENV["OPENAI_API_KEY"] = "test-key-placeholder"
    ScenarioCatalog.reload!
    @game = games(:romeo_game)
    @game.update!(world_state: OutcomeResolutionService.initial_state.merge(
      "act_number" => 1, "act_turn" => 0, "player_scene" => "cell"
    ))
  end

  test "does not compress when fewer than threshold notes" do
    9.times do |i|
      Turn.create!(game: @game, act: acts(:act_one), turn_number: i + 1,
                   content: "Narrative #{i}", llm_memory: "Note #{i}")
    end

    AIClient.expects(:chat_json).never
    result = MemoryCompressionService.maybe_compress!(@game)
    assert_equal false, result
  end

  test "compresses oldest 5 notes and keeps recent 5" do
    10.times do |i|
      Turn.create!(game: @game, act: acts(:act_one), turn_number: i + 1,
                   content: "Narrative #{i}", llm_memory: "Note #{i}")
    end

    AIClient.stubs(:chat_json).returns([ { "summary" => "Compressed story summary." }, 50 ])

    result = MemoryCompressionService.maybe_compress!(@game)
    assert_equal true, result

    @game.reload
    assert_equal "Compressed story summary.", @game.memory_summary

    remaining = @game.turns.where.not(llm_memory: [ nil, "" ]).order(:turn_number)
    assert_equal 5, remaining.count
    assert_equal (6..10).to_a, remaining.pluck(:turn_number)
  end

  test "incremental compression passes existing summary and only oldest notes" do
    @game.update!(memory_summary: "Previous summary of events.")
    10.times do |i|
      Turn.create!(game: @game, act: acts(:act_one), turn_number: i + 1,
                   content: "Narrative #{i}", llm_memory: "Note #{i}")
    end

    captured_message = nil
    AIClient.stubs(:chat_json).with do |args|
      captured_message = args[:user_message]
      true
    end.returns([ { "summary" => "Updated summary." }, 50 ])

    MemoryCompressionService.maybe_compress!(@game)

    assert_includes captured_message, "PREVIOUS SUMMARY:"
    assert_includes captured_message, "Previous summary of events."
    assert_includes captured_message, "MEMORY NOTES TO COMPRESS:"
    # Only oldest 5 notes sent to compression
    assert_includes captured_message, "T1 - Note 0"
    assert_includes captured_message, "T5 - Note 4"
    refute_includes captured_message, "T6 - Note 5"
  end

  test "uses difficulty model and low temperature" do
    10.times do |i|
      Turn.create!(game: @game, act: acts(:act_one), turn_number: i + 1,
                   content: "Narrative #{i}", llm_memory: "Note #{i}")
    end

    AIClient.stubs(:chat_json).with do |args|
      args[:model] == AIClient.difficulty_model && args[:temperature] == 0.2
    end.returns([ { "summary" => "Summary." }, 50 ])

    result = MemoryCompressionService.maybe_compress!(@game)
    assert_equal true, result
  end
end
