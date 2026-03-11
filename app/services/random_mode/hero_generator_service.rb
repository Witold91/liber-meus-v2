module RandomMode
  class HeroGeneratorService
    SYSTEM_PROMPT_PATH = Rails.root.join("lib", "prompts", "random_hero_generator.txt")

    def self.generate(hero_description, world_context:, game_language: "en")
      system_prompt = File.read(SYSTEM_PROMPT_PATH)
      system_prompt += "\n\nIMPORTANT: Write all prose and descriptions in #{language_name(game_language)}. Names of characters and items should be immersive and fit the world's culture and setting — not the output language."

      AIClient.chat_json(
        system_prompt: system_prompt,
        user_message: "WORLD CONTEXT:\n#{world_context}\n\nHERO DESCRIPTION:\n#{hero_description}",
        model: AIClient.narrator_model,
        temperature: 0.7,
        service_name: "RandomMode::HeroGeneratorService"
      )
    end

    def self.language_name(locale)
      { "en" => "English", "pl" => "Polish" }[locale.to_s] || "English"
    end
    private_class_method :language_name
  end
end
