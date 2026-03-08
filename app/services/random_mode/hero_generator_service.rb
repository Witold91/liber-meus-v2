module RandomMode
  class HeroGeneratorService
    SYSTEM_PROMPT_PATH = Rails.root.join("lib", "prompts", "random_hero_generator.txt")

    def self.generate(hero_description, world_context:, game_language: "en")
      client = AIClient.client
      model = AIClient.narrator_model

      system_prompt = File.read(SYSTEM_PROMPT_PATH)
      system_prompt += "\n\nIMPORTANT: Generate all text content in #{language_name(game_language)}."

      user_message = "WORLD CONTEXT:\n#{world_context}\n\nHERO DESCRIPTION:\n#{hero_description}"

      response = client.chat(
        parameters: {
          model: model,
          temperature: 0.7,
          response_format: { type: "json_object" },
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: user_message }
          ]
        }
      )

      content = response.dig("choices", 0, "message", "content")
      tokens = response.dig("usage", "total_tokens").to_i
      [ JSON.parse(content), tokens ]
    rescue => e
      Rails.logger.error("[RandomMode::HeroGeneratorService] Error: #{e.message}")
      raise AIConnectionError, e.message
    end

    def self.language_name(locale)
      { "en" => "English", "pl" => "Polish" }[locale.to_s] || "English"
    end
    private_class_method :language_name
  end
end
