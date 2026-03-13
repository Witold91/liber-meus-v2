require "test_helper"

class EmbeddingServiceTest < ActiveSupport::TestCase
  setup do
    ENV["OPENAI_API_KEY"] = "test-key-placeholder"
  end

  test "embed returns array of vectors for multiple texts" do
    mock_response = {
      "data" => [
        { "index" => 0, "embedding" => [0.1] * 1536 },
        { "index" => 1, "embedding" => [0.2] * 1536 }
      ]
    }
    mock_client = mock("client")
    mock_client.expects(:embeddings).with(
      parameters: {
        model: "text-embedding-3-small",
        input: ["hello", "world"]
      }
    ).returns(mock_response)
    AIClient.stubs(:client).returns(mock_client)

    result = EmbeddingService.embed(["hello", "world"])
    assert_equal 2, result.length
    assert_equal 1536, result[0].length
    assert_equal 0.1, result[0][0]
    assert_equal 0.2, result[1][0]
  end

  test "embed returns results sorted by index" do
    mock_response = {
      "data" => [
        { "index" => 1, "embedding" => [0.2] * 1536 },
        { "index" => 0, "embedding" => [0.1] * 1536 }
      ]
    }
    mock_client = mock("client")
    mock_client.expects(:embeddings).returns(mock_response)
    AIClient.stubs(:client).returns(mock_client)

    result = EmbeddingService.embed(["first", "second"])
    assert_equal 0.1, result[0][0]
    assert_equal 0.2, result[1][0]
  end

  test "embed returns empty array for blank input" do
    assert_equal [], EmbeddingService.embed([])
    assert_equal [], EmbeddingService.embed(nil)
  end

  test "embed_single returns single vector" do
    mock_response = {
      "data" => [
        { "index" => 0, "embedding" => [0.5] * 1536 }
      ]
    }
    mock_client = mock("client")
    mock_client.expects(:embeddings).returns(mock_response)
    AIClient.stubs(:client).returns(mock_client)

    result = EmbeddingService.embed_single("hello")
    assert_equal 1536, result.length
    assert_equal 0.5, result[0]
  end

  test "uses custom model from environment" do
    ENV["AI_EMBEDDING_MODEL"] = "custom-model"
    mock_response = { "data" => [{ "index" => 0, "embedding" => [0.1] * 1536 }] }
    mock_client = mock("client")
    mock_client.expects(:embeddings).with(
      parameters: { model: "custom-model", input: ["test"] }
    ).returns(mock_response)
    AIClient.stubs(:client).returns(mock_client)

    EmbeddingService.embed(["test"])
  ensure
    ENV.delete("AI_EMBEDDING_MODEL")
  end
end
