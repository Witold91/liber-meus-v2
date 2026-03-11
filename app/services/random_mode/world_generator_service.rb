module RandomMode
  class WorldGeneratorService
    SYSTEM_PROMPT_PATH = Rails.root.join("lib", "prompts", "random_world_generator.txt")
    THEMES_PATH = Rails.root.join("config", "random_themes.yml")

    def self.generate(setting_description, game_language: "en")
      system_prompt = File.read(SYSTEM_PROMPT_PATH)
      system_prompt.gsub!("{{THEME_OPTIONS}}", theme_options_for_prompt)
      system_prompt += "\n\nIMPORTANT: Write all prose and descriptions in #{language_name(game_language)}. Names of characters, locations, and items should be immersive and fit the world's culture and setting — not the output language."

      AIClient.chat_json(
        system_prompt: system_prompt,
        user_message: "SETTING DESCRIPTION:\n#{setting_description}",
        model: AIClient.narrator_model,
        temperature: 0.8,
        service_name: "RandomMode::WorldGeneratorService"
      )
    end

    def self.themes
      @themes ||= YAML.load_file(THEMES_PATH)
    end

    def self.resolve_theme(theme_id)
      themes[theme_id.to_s] || themes.values.first
    end

    def self.theme_options_for_prompt
      themes.map { |id, t| "  - \"#{id}\": #{t["name"]}" }.join("\n")
    end
    private_class_method :theme_options_for_prompt

    def self.language_name(locale)
      { "en" => "English", "pl" => "Polish" }[locale.to_s] || "English"
    end
    private_class_method :language_name
  end
end
