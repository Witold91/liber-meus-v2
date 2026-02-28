class ArenaNarratorService
  SYSTEM_PROMPT_PATH = Rails.root.join("lib", "prompts", "arena_narrator.txt")

  def self.narrate(action, resolution_tag, difficulty, scene_context, turn_context, health_loss = 0, world_context: nil, narrator_style: nil)
    client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))
    model = ENV.fetch("AI_NARRATOR_MODEL", "gpt-4o-mini")

    system_prompt = File.read(SYSTEM_PROMPT_PATH)
    system_prompt += "\n\nWORLD CONTEXT:\n#{world_context.strip}" if world_context.present?
    system_prompt += "\n\nSTYLE DIRECTIVE:\n#{narrator_style.strip}" if narrator_style.present?
    user_message = build_user_message(action, resolution_tag, difficulty, scene_context, turn_context, health_loss)

    response = client.chat(
      parameters: {
        model: model,
        temperature: 0.7,
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
    Rails.logger.error("[ArenaNarratorService] Error: #{e.message}")
    raise AIConnectionError, e.message
  end

  def self.build_user_message(action, resolution_tag, difficulty, scene_context, turn_context, health_loss = 0)
    parts = []
    localized_resolution = I18n.t("game.resolution_tags.#{resolution_tag}", default: resolution_tag).upcase
    localized_difficulty = I18n.t("game.difficulty_values.#{difficulty}", default: difficulty)
    parts << I18n.t(
      "services.arena_narrator_service.prompt.resolution",
      resolution: localized_resolution,
      difficulty: localized_difficulty
    )
    if (reasoning = turn_context[:rating_reasoning]).present?
      parts << I18n.t("services.arena_narrator_service.prompt.rating_reasoning", reasoning: reasoning)
    end
    parts << ""
    parts << I18n.t(
      "services.arena_narrator_service.prompt.current_scene",
      scene_name: scene_context.dig(:scene, :name),
      scene_id: scene_context.dig(:scene, :id)
    )
    parts << scene_context.dig(:scene, :description).to_s
    parts << ""

    if scene_context[:actors].any?
      parts << I18n.t("services.arena_narrator_service.prompt.actors_present")
      scene_context[:actors].each do |a|
        parts << I18n.t(
          "services.arena_narrator_service.prompt.actor_item",
          id: a[:id],
          name: a[:name],
          description: a[:description],
          statuses: a[:statuses].join(", ")
        )
      end
      parts << ""
    end

    if scene_context[:objects].any?
      parts << I18n.t("services.arena_narrator_service.prompt.objects_present")
      scene_context[:objects].each do |o|
        parts << I18n.t(
          "services.arena_narrator_service.prompt.object_item",
          id: o[:id],
          name: o[:name],
          statuses: o[:statuses].join(", ")
        )
      end
      parts << ""
    end

    if scene_context[:exits].any?
      parts << I18n.t(
        "services.arena_narrator_service.prompt.exits",
        exits: scene_context[:exits].map { |e| "#{e["label"]} (to: #{e["to"]})" }.join(", ")
      )
      parts << ""
    end

    delta = turn_context[:world_state_delta] || []
    if delta.any?
      parts << I18n.t("services.arena_narrator_service.prompt.world_state_header")
      delta.each do |d|
        status_label = I18n.t("game.status_values.#{d[:status]}", default: d[:status].to_s)
        info = d[:scene] ? "#{status_label} (at #{d[:scene]})" : status_label
        parts << I18n.t(
          "services.arena_narrator_service.prompt.world_state_item",
          name: d[:name],
          id: d[:id],
          info: info
        )
      end
      parts << ""
    end

    memory_notes = turn_context[:memory_notes] || []
    if memory_notes.any?
      parts << I18n.t("services.arena_narrator_service.prompt.story_so_far_header")
      memory_notes.each do |note|
        parts << I18n.t("services.arena_narrator_service.prompt.memory_note_item", note: note[:note])
      end
      parts << ""
    end

    recent_actions = turn_context[:recent_actions] || []
    if recent_actions.any?
      parts << I18n.t("services.arena_narrator_service.prompt.recent_actions_header")
      recent_actions.each do |ra|
        localized_res = I18n.t("game.resolution_tags.#{ra[:resolution]}", default: ra[:resolution].to_s)
        parts << I18n.t(
          "services.arena_narrator_service.prompt.recent_action_item",
          turn_number: ra[:turn_number],
          action: ra[:action],
          resolution: localized_res
        )
      end
      parts << ""
    end

    if health_loss > 0
      parts << I18n.t("services.arena_narrator_service.prompt.health_loss", amount: health_loss)
      parts << ""
    end

    parts << I18n.t("services.arena_narrator_service.prompt.player_action", action: action)
    parts.join("\n")
  end
  private_class_method :build_user_message
end
