class EmbeddingService
  def self.embed(texts)
    return [] if texts.blank?

    model = ENV.fetch("AI_EMBEDDING_MODEL", "text-embedding-3-small")
    response = AIClient.client.embeddings(
      parameters: {
        model: model,
        input: texts
      }
    )

    response.dig("data").sort_by { |d| d["index"] }.map { |d| d["embedding"] }
  end

  def self.embed_single(text)
    embed([text]).first
  end
end
