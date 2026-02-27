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
    @recent_turns = []
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
    client_mock.expects(:chat).returns(fake_response)
    OpenAI::Client.expects(:new).returns(client_mock)

    result, tokens = ArenaNarratorService.narrate("Remove the grate", "success", "easy", @stage_context, @recent_turns)
    assert result.key?("narrative")
    assert result.key?("diff")
    assert_equal "removed", result.dig("diff", "object_updates", "loose_grate", "status")
    assert_equal 87, tokens
  end

  test "narrate raises AIConnectionError on API error" do
    OpenAI::Client.expects(:new).raises(StandardError, "network error")

    assert_raises(::AIConnectionError) do
      ArenaNarratorService.narrate("Do something", "success", "easy", @stage_context, @recent_turns)
    end
  end
end
