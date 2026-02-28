class ArenaNarratorService
  SYSTEM_PROMPT_PATH = Rails.root.join("lib", "prompts", "arena_narrator.txt")

  def self.narrate(action, resolution_tag, difficulty, stage_context, recent_turns, health_loss = 0)
    client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))
    model = ENV.fetch("AI_NARRATOR_MODEL", "gpt-4o-mini")

    system_prompt = File.read(SYSTEM_PROMPT_PATH)
    user_message = build_user_message(action, resolution_tag, difficulty, stage_context, recent_turns, health_loss)

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

  def self.build_user_message(action, resolution_tag, difficulty, stage_context, recent_turns, health_loss = 0)
    parts = []
    localized_resolution = I18n.t("game.resolution_tags.#{resolution_tag}", default: resolution_tag).upcase
    localized_difficulty = I18n.t("game.difficulty_values.#{difficulty}", default: difficulty)
    parts << I18n.t(
      "services.arena_narrator_service.prompt.resolution",
      resolution: localized_resolution,
      difficulty: localized_difficulty
    )
    parts << ""
    parts << I18n.t(
      "services.arena_narrator_service.prompt.current_stage",
      stage_name: stage_context.dig(:stage, :name),
      stage_id: stage_context.dig(:stage, :id)
    )
    parts << stage_context.dig(:stage, :description).to_s
    parts << ""

    if stage_context[:actors].any?
      parts << I18n.t("services.arena_narrator_service.prompt.actors_present")
      stage_context[:actors].each do |a|
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

    if stage_context[:objects].any?
      parts << I18n.t("services.arena_narrator_service.prompt.objects_present")
      stage_context[:objects].each do |o|
        parts << I18n.t(
          "services.arena_narrator_service.prompt.object_item",
          id: o[:id],
          name: o[:name],
          statuses: o[:statuses].join(", ")
        )
      end
      parts << ""
    end

    if stage_context[:exits].any?
      parts << I18n.t(
        "services.arena_narrator_service.prompt.exits",
        exits: stage_context[:exits].map { |e| "#{e["label"]} (to: #{e["to"]})" }.join(", ")
      )
      parts << ""
    end

    if recent_turns.any?
      parts << I18n.t("services.arena_narrator_service.prompt.recent_history")
      recent_turns.reverse.each do |t|
        parts << I18n.t(
          "services.arena_narrator_service.prompt.turn_history",
          turn_number: t.turn_number,
          content: t.content.to_s.truncate(200)
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
