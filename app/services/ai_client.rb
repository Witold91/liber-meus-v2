class AIClient
  def self.client
    OpenAI::Client.new(
      access_token: ENV.fetch("OPENAI_API_KEY"),
      uri_base: ENV.fetch("AI_BASE_URL", "https://api.openai.com")
    )
  end

  # High-level: chat + parse JSON response. Returns [parsed_hash, tokens].
  # Wraps error handling with AIConnectionError.
  def self.chat_json(system_prompt:, user_message:, model:, temperature:, service_name:)
    parameters = {
      model: model,
      temperature: temperature,
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: user_message }
      ]
    }.merge(json_response_format)

    response = chat(parameters: parameters, service_name: service_name)

    content = response.dig("choices", 0, "message", "content")
    tokens = response.dig("usage", "total_tokens").to_i
    [ parse_json(content), tokens ]
  rescue => e
    Rails.logger.error("[#{service_name}] Error: #{e.message}")
    raise AIConnectionError, e.message
  end

  def self.chat(parameters:, service_name: "unknown")
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = client.chat(parameters: parameters)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

    log_request(
      service_name: service_name,
      parameters: parameters,
      response_body: response,
      tokens: response.dig("usage", "total_tokens").to_i,
      duration_ms: duration_ms
    )

    response
  end

  def self.chat_streaming(parameters:, service_name: "unknown")
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = client.chat(parameters: parameters)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

    log = log_request(
      service_name: service_name,
      parameters: parameters.except(:stream, :stream_options),
      response_body: nil,
      tokens: 0,
      duration_ms: duration_ms
    )

    [ response, log ]
  end

  def self.complete_streaming_log(log, response_body:, tokens:)
    return unless log

    log.update!(response_body: response_body, tokens_used: tokens)
  rescue => e
    Rails.logger.warn("[AIClient] Failed to update streaming log: #{e.message}")
  end

  def self.log_request(service_name:, parameters:, response_body:, tokens:, duration_ms:)
    return unless Rails.env.development?

    AIRequestLog.create!(
      service_name: service_name,
      model: parameters[:model],
      temperature: parameters[:temperature],
      messages: parameters[:messages],
      response_body: response_body,
      tokens_used: tokens,
      duration_ms: duration_ms
    )
  rescue => e
    Rails.logger.warn("[AIClient] Failed to log AI request: #{e.message}")
  end

  def self.log_error(service_name:, parameters:, error:, duration_ms:)
    return unless Rails.env.development?

    AIRequestLog.create!(
      service_name: service_name,
      model: parameters[:model],
      temperature: parameters[:temperature],
      messages: parameters[:messages],
      error_message: error.message,
      duration_ms: duration_ms
    )
  rescue => e
    Rails.logger.warn("[AIClient] Failed to log AI error: #{e.message}")
  end

  def self.difficulty_model
    ENV.fetch("AI_DIFFICULTY_MODEL", "gpt-4o-mini")
  end

  def self.narrator_model
    ENV.fetch("AI_NARRATOR_MODEL", "gpt-4o-mini")
  end

  # Returns response_format hash for JSON mode when the provider supports it.
  # Set AI_JSON_MODE=true for providers that support OpenAI-style json_object
  # response format (e.g. OpenAI, DeepSeek). Defaults to true for OpenAI.
  def self.json_response_format
    return {} unless json_mode?
    { response_format: { type: "json_object" } }
  end

  def self.parse_json(raw)
    cleaned = raw.strip
    cleaned = cleaned.delete_prefix("```json").delete_prefix("```")
    cleaned = cleaned.delete_suffix("```")
    JSON.parse(cleaned.strip)
  end

  def self.json_mode?
    ENV.fetch("AI_JSON_MODE") { ENV.fetch("AI_BASE_URL", "https://api.openai.com").include?("openai.com") }
      .to_s == "true"
  end
end
