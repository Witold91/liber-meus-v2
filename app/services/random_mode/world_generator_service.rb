module RandomMode
  class WorldGeneratorService
    SYSTEM_PROMPT_PATH = Rails.root.join("lib", "prompts", "random_world_generator.txt")
    THEMES_PATH = Rails.root.join("config", "random_themes.yml")

    def self.generate(setting_description, game_language: "en")
      client = AIClient.client
      model = AIClient.narrator_model

      system_prompt = File.read(SYSTEM_PROMPT_PATH)
      system_prompt.gsub!("{{THEME_OPTIONS}}", theme_options_for_prompt)
      system_prompt += "\n\nIMPORTANT: Write all prose and descriptions in #{language_name(game_language)}. Names of characters, locations, and items should be immersive and fit the world's culture and setting — not the output language."

      user_message = "SETTING DESCRIPTION:\n#{setting_description}"

      response = client.chat(
        parameters: {
          model: model,
          temperature: 0.8,
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
      Rails.logger.error("[Random::WorldGeneratorService] Error: #{e.message}")
      raise AIConnectionError, e.message
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
