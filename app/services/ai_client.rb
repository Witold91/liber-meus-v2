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
end
