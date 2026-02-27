class ArenaNarratorService
  SYSTEM_PROMPT_PATH = Rails.root.join("lib", "prompts", "arena_narrator.txt")

  def self.narrate(action, resolution_tag, difficulty, stage_context, recent_turns)
    client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))
    model = ENV.fetch("AI_NARRATOR_MODEL", "gpt-4o-mini")

    system_prompt = File.read(SYSTEM_PROMPT_PATH)
    user_message = build_user_message(action, resolution_tag, difficulty, stage_context, recent_turns)

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
    [ fallback_response(action, resolution_tag), 0 ]
  end

  def self.build_user_message(action, resolution_tag, difficulty, stage_context, recent_turns)
    parts = []
    localized_resolution = I18n.t("game.resolution_tags.#{resolution_tag}", default: resolution_tag).upcase
    localized_difficulty = I18n.t("game.difficulty_values.#{difficulty}", default: difficulty)
    parts << I18n.t(
      "services.arena_narrator_service.prompt.resolution",
      resolution: localized_resolution,
      difficulty: localized_difficulty
    )
    parts << ""
    parts << I18n.t("services.arena_narrator_service.prompt.current_stage", stage_name: stage_context.dig(:stage, :name))
    parts << stage_context.dig(:stage, :description).to_s
    parts << ""

    if stage_context[:actors].any?
      parts << I18n.t("services.arena_narrator_service.prompt.actors_present")
      stage_context[:actors].each do |a|
        parts << I18n.t(
          "services.arena_narrator_service.prompt.actor_item",
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
        parts << I18n.t("services.arena_narrator_service.prompt.object_item", name: o[:name], statuses: o[:statuses].join(", "))
      end
      parts << ""
    end

    if stage_context[:exits].any?
      parts << I18n.t(
        "services.arena_narrator_service.prompt.exits",
        exits: stage_context[:exits].map { |e| e["label"] }.join(", ")
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

    parts << I18n.t("services.arena_narrator_service.prompt.player_action", action: action)
    parts.join("\n")
  end
  private_class_method :build_user_message

  def self.fallback_response(action, resolution_tag)
    narrative = case resolution_tag
    when "success"
      I18n.t("services.arena_narrator_service.fallback.success")
    when "partial"
      I18n.t("services.arena_narrator_service.fallback.partial")
    else
      I18n.t("services.arena_narrator_service.fallback.failure")
    end

    { "narrative" => narrative, "diff" => {} }
  end
  private_class_method :fallback_response
end
