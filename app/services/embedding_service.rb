class EmbeddingService
  def self.embed(texts)
    return [] if texts.blank?

    model = ENV.fetch("AI_EMBEDDING_MODEL", "text-embedding-3-small")
    parameters = { model: model, input: texts }

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = AIClient.client.embeddings(parameters: parameters)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

    tokens = response.dig("usage", "total_tokens").to_i
    AIClient.log_request(
      service_name: "EmbeddingService",
      parameters: { model: model, messages: texts },
      response_body: { token_count: tokens, embedding_count: response.dig("data")&.size },
      tokens: tokens,
      duration_ms: duration_ms
    )

    response.dig("data").sort_by { |d| d["index"] }.map { |d| d["embedding"] }
  end

  def self.embed_single(text)
    embed([ text ]).first
  end
end
