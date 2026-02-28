require "test_helper"

class ArenaNarratorServiceTest < ActiveSupport::TestCase
  setup do
    @original_key = ENV["OPENAI_API_KEY"]
    ENV["OPENAI_API_KEY"] = "test-key-placeholder"
    @stage_context = {
      stage: { id: "cell", name: "Your Cell", description: "A 6x9 concrete box." },
      actors: [],
      objects: [ { id: "loose_grate", name: "Loose Ventilation Grate", statuses: [ "in_place" ] } ],
      exits: []
    }
    @turn_context = { world_state_delta: [], memory_notes: [], recent_actions: [] }
  end

  teardown do
    if @original_key
      ENV["OPENAI_API_KEY"] = @original_key
    else
      ENV.delete("OPENAI_API_KEY")
    end
  end

  test "narrate returns hash with narrative and diff and token count" do
    payload = {
      "narrative" => "You carefully pry the grate free.",
      "diff" => { "object_updates" => { "loose_grate" => { "status" => "removed" } } }
    }
    fake_response = {
      "choices" => [ { "message" => { "content" => payload.to_json } } ],
      "usage" => { "total_tokens" => 87 }
    }
    client_mock = mock
    client_mock.expects(:chat).with do |request|
      user_message = request.dig(:parameters, :messages, 1, :content)
      assert_includes user_message, "[id=cell]"
      assert_includes user_message, "[id=loose_grate]"
      true
    end.returns(fake_response)
    OpenAI::Client.expects(:new).returns(client_mock)

    result, tokens = ArenaNarratorService.narrate("Remove the grate", "success", "easy", @stage_context, @turn_context)
    assert result.key?("narrative")
    assert result.key?("diff")
    assert_equal "removed", result.dig("diff", "object_updates", "loose_grate", "status")
    assert_equal 87, tokens
  end

  test "health_loss is included in user message when non-zero" do
    fake_response = {
      "choices" => [ { "message" => { "content" => { "narrative" => "You are struck.", "diff" => {} }.to_json } } ],
      "usage" => { "total_tokens" => 50 }
    }
    client_mock = mock
    client_mock.expects(:chat).with do |request|
      user_message = request.dig(:parameters, :messages, 1, :content)
      assert_includes user_message, "HEALTH LOST: 18"
      true
    end.returns(fake_response)
    OpenAI::Client.expects(:new).returns(client_mock)

    ArenaNarratorService.narrate("Fight the guard", "failure", "medium", @stage_context, @turn_context, 18)
  end

  test "health_loss line is absent when zero" do
    fake_response = {
      "choices" => [ { "message" => { "content" => { "narrative" => "You look around.", "diff" => {} }.to_json } } ],
      "usage" => { "total_tokens" => 40 }
    }
    client_mock = mock
    client_mock.expects(:chat).with do |request|
      user_message = request.dig(:parameters, :messages, 1, :content)
      assert_not_includes user_message, "HEALTH LOST"
      true
    end.returns(fake_response)
    OpenAI::Client.expects(:new).returns(client_mock)

    ArenaNarratorService.narrate("Look around", "success", "trivial", @stage_context, @turn_context, 0)
  end

  test "world_state_delta is included in user message when present" do
    fake_response = {
      "choices" => [ { "message" => { "content" => { "narrative" => "You act.", "diff" => {} }.to_json } } ],
      "usage" => { "total_tokens" => 30 }
    }
    client_mock = mock
    client_mock.expects(:chat).with do |request|
      user_message = request.dig(:parameters, :messages, 1, :content)
      assert_includes user_message, "WORLD STATE"
      assert_includes user_message, "[id=guard_rodriguez]"
      true
    end.returns(fake_response)
    OpenAI::Client.expects(:new).returns(client_mock)

    turn_context = {
      world_state_delta: [ { type: "actor", id: "guard_rodriguez", name: "Guard Rodriguez", status: "distracted", stage: nil } ],
      memory_notes: [],
      recent_actions: []
    }
    ArenaNarratorService.narrate("Look around", "success", "easy", @stage_context, turn_context)
  end

  test "memory_notes are included in user message when present" do
    fake_response = {
      "choices" => [ { "message" => { "content" => { "narrative" => "You act.", "diff" => {} }.to_json } } ],
      "usage" => { "total_tokens" => 30 }
    }
    client_mock = mock
    client_mock.expects(:chat).with do |request|
      user_message = request.dig(:parameters, :messages, 1, :content)
      assert_includes user_message, "STORY SO FAR"
      assert_includes user_message, "Torres agreed to help"
      true
    end.returns(fake_response)
    OpenAI::Client.expects(:new).returns(client_mock)

    turn_context = {
      world_state_delta: [],
      memory_notes: [ { turn_number: 1, note: "Torres agreed to help" } ],
      recent_actions: []
    }
    ArenaNarratorService.narrate("Crawl through shaft", "success", "easy", @stage_context, turn_context)
  end

  test "recent_actions are included in user message when present" do
    fake_response = {
      "choices" => [ { "message" => { "content" => { "narrative" => "You act.", "diff" => {} }.to_json } } ],
      "usage" => { "total_tokens" => 30 }
    }
    client_mock = mock
    client_mock.expects(:chat).with do |request|
      user_message = request.dig(:parameters, :messages, 1, :content)
      assert_includes user_message, "RECENT ACTIONS"
      assert_includes user_message, "remove the grate"
      true
    end.returns(fake_response)
    OpenAI::Client.expects(:new).returns(client_mock)

    turn_context = {
      world_state_delta: [],
      memory_notes: [],
      recent_actions: [ { turn_number: 1, action: "remove the grate", resolution: "success" } ]
    }
    ArenaNarratorService.narrate("Crawl through shaft", "success", "easy", @stage_context, turn_context)
  end

  test "world_context is prepended to system prompt before style directive" do
    fake_response = {
      "choices" => [ { "message" => { "content" => { "narrative" => "You act.", "diff" => {} }.to_json } } ],
      "usage" => { "total_tokens" => 30 }
    }
    client_mock = mock
    client_mock.expects(:chat).with do |request|
      system_prompt = request.dig(:parameters, :messages, 0, :content)
      assert_includes system_prompt, "WORLD CONTEXT"
      assert_includes system_prompt, "Renaissance Verona"
      world_pos = system_prompt.index("WORLD CONTEXT")
      style_pos = system_prompt.index("STYLE DIRECTIVE")
      assert world_pos < style_pos, "WORLD CONTEXT should appear before STYLE DIRECTIVE"
      true
    end.returns(fake_response)
    OpenAI::Client.expects(:new).returns(client_mock)

    ArenaNarratorService.narrate("Look around", "success", "trivial", @stage_context, @turn_context, 0,
      world_context: "Renaissance Verona, late at night.",
      narrator_style: "Write tersely.")
  end

  test "narrator_style is appended to system prompt when provided" do
    fake_response = {
      "choices" => [ { "message" => { "content" => { "narrative" => "You act.", "diff" => {} }.to_json } } ],
      "usage" => { "total_tokens" => 30 }
    }
    client_mock = mock
    client_mock.expects(:chat).with do |request|
      system_prompt = request.dig(:parameters, :messages, 0, :content)
      assert_includes system_prompt, "STYLE DIRECTIVE"
      assert_includes system_prompt, "terse"
      true
    end.returns(fake_response)
    OpenAI::Client.expects(:new).returns(client_mock)

    ArenaNarratorService.narrate("Look around", "success", "trivial", @stage_context, @turn_context, 0, narrator_style: "Write in a terse style.")
  end

  test "narrate raises AIConnectionError on API error" do
    OpenAI::Client.expects(:new).raises(StandardError, "network error")

    assert_raises(::AIConnectionError) do
      ArenaNarratorService.narrate("Do something", "success", "easy", @stage_context, @turn_context)
    end
  end
end
