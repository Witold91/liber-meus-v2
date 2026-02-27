require "test_helper"

class DifficultyRatingServiceTest < ActiveSupport::TestCase
  setup do
    @original_key = ENV["OPENAI_API_KEY"]
    ENV["OPENAI_API_KEY"] = "test-key-placeholder"
    @hero = heroes(:convict)
    @stage_context = {
      stage: { id: "cell", name: "Your Cell", description: "A 6x9 concrete box." },
      actors: [],
      objects: [ { id: "loose_grate", name: "Loose Ventilation Grate", statuses: [ "in_place" ] } ],
      exits: [ { "label" => "Ventilation grate (above bunk)", "to" => "vent_shaft" } ]
    }
  end

  teardown do
    if @original_key
      ENV["OPENAI_API_KEY"] = @original_key
    else
      ENV.delete("OPENAI_API_KEY")
    end
  end

  test "rate returns a hash with difficulty key and token count" do
    fake_response = {
      "choices" => [ { "message" => { "content" => '{"difficulty":"easy","reasoning":"No guards present."}' } } ],
      "usage" => { "total_tokens" => 42 }
    }
    client_mock = mock
    client_mock.expects(:chat).returns(fake_response)
    OpenAI::Client.expects(:new).returns(client_mock)

    result, tokens = DifficultyRatingService.rate("Remove the grate", @stage_context, @hero)
    assert_equal "easy", result["difficulty"]
    assert result.key?("reasoning")
    assert_equal 42, tokens
  end

  test "rate raises AIConnectionError on API error" do
    OpenAI::Client.expects(:new).raises(StandardError, "network error")

    assert_raises(::AIConnectionError) do
      DifficultyRatingService.rate("Do something", @stage_context, @hero)
    end
  end

  test "rate raises AIConnectionError on JSON parse error" do
    fake_response = {
      "choices" => [ { "message" => { "content" => "not valid json" } } ],
      "usage" => { "total_tokens" => 10 }
    }
    client_mock = mock
    client_mock.expects(:chat).returns(fake_response)
    OpenAI::Client.expects(:new).returns(client_mock)

    assert_raises(::AIConnectionError) do
      DifficultyRatingService.rate("Do something", @stage_context, @hero)
    end
  end
end
