module RandomMode
  class SceneGeneratorService
    SYSTEM_PROMPT_PATH = Rails.root.join("lib", "prompts", "random_scene_generator.txt")

    def self.generate(world_context:, existing_scenes:, origin_scene_id:, exit_label:, player_inventory: [], memory_notes: [], game_language: "en")
      client = AIClient.client
      model = AIClient.narrator_model

      system_prompt = File.read(SYSTEM_PROMPT_PATH)
      system_prompt += "\n\nIMPORTANT: Generate all text content in #{language_name(game_language)}."

      user_message = build_user_message(
        world_context: world_context,
        existing_scenes: existing_scenes,
        origin_scene_id: origin_scene_id,
        exit_label: exit_label,
        player_inventory: player_inventory,
        memory_notes: memory_notes
      )

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
      Rails.logger.error("[RandomMode::SceneGeneratorService] Error: #{e.message}")
      raise AIConnectionError, e.message
    end

    def self.build_user_message(world_context:, existing_scenes:, origin_scene_id:, exit_label:, player_inventory:, memory_notes:)
      parts = []
      parts << "WORLD CONTEXT:\n#{world_context}"
      parts << ""

      parts << "EXISTING SCENES:"
      existing_scenes.each do |scene|
        exit_labels = (scene["exits"] || []).map { |e| "#{e["label"]} (to: #{e["to"]})" }.join(", ")
        parts << "- #{scene["id"]}: #{scene["name"]} [exits: #{exit_labels}]"
      end
      parts << ""

      parts << "ORIGIN SCENE: #{origin_scene_id}"
      parts << "EXIT USED: #{exit_label}"
      parts << ""

      if player_inventory.any?
        parts << "PLAYER INVENTORY:"
        player_inventory.each { |item| parts << "- #{item[:name]} (#{item[:statuses].join(", ")})" }
        parts << ""
      end

      if memory_notes.any?
        parts << "STORY NOTES:"
        memory_notes.each { |note| parts << "- #{note[:note]}" }
        parts << ""
      end

      parts.join("\n")
    end
    private_class_method :build_user_message

    def self.language_name(locale)
      { "en" => "English", "pl" => "Polish" }[locale.to_s] || "English"
    end
    private_class_method :language_name
  end
end
