class AIClient
  def self.client
    OpenAI::Client.new(
      access_token: ENV.fetch("OPENAI_API_KEY"),
      uri_base: ENV.fetch("AI_BASE_URL", "https://api.openai.com")
    )
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
