class DifficultyRatingService
  SYSTEM_PROMPT_PATH = Rails.root.join("lib", "prompts", "difficulty_rating.txt")

  def self.rate(action, scene_context, hero, recent_actions = [], world_context: nil)
    client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))
    model = ENV.fetch("AI_DIFFICULTY_MODEL", "gpt-4o-mini")

    system_prompt = File.read(SYSTEM_PROMPT_PATH)
    system_prompt += "\n\nWORLD CONTEXT:\n#{world_context.strip}" if world_context.present?
    user_message = build_user_message(action, scene_context, hero, recent_actions)

    response = client.chat(
      parameters: {
        model: model,
        temperature: 0.2,
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
    Rails.logger.error("[DifficultyRatingService] Error: #{e.message}")
    raise AIConnectionError, e.message
  end

  def self.build_user_message(action, scene_context, hero, recent_actions = [])
    parts = []
    parts << I18n.t("services.difficulty_rating_service.prompt.hero", name: hero.name, description: hero.description)
    parts << ""
    parts << I18n.t("services.difficulty_rating_service.prompt.current_scene", scene_name: scene_context.dig(:scene, :name))
    parts << scene_context.dig(:scene, :description).to_s
    parts << ""

    if scene_context[:actors].any?
      parts << I18n.t("services.difficulty_rating_service.prompt.actors_present")
      scene_context[:actors].each do |a|
        parts << I18n.t("services.difficulty_rating_service.prompt.list_item", name: a[:name], statuses: a[:statuses].join(", "))
      end
      parts << ""
    end

    if scene_context[:objects].any?
      parts << I18n.t("services.difficulty_rating_service.prompt.objects_present")
      scene_context[:objects].each do |o|
        parts << I18n.t("services.difficulty_rating_service.prompt.list_item", name: o[:name], statuses: o[:statuses].join(", "))
      end
      parts << ""
    end

    if recent_actions.any?
      parts << I18n.t("services.difficulty_rating_service.prompt.recent_actions_header")
      recent_actions.each do |ra|
        localized_res = I18n.t("game.resolution_tags.#{ra[:resolution]}", default: ra[:resolution].to_s)
        parts << I18n.t(
          "services.difficulty_rating_service.prompt.recent_action_item",
          turn_number: ra[:turn_number],
          action: ra[:action],
          resolution: localized_res
        )
      end
      parts << ""
    end

    parts << I18n.t("services.difficulty_rating_service.prompt.player_action", action: action)
    parts.join("\n")
  end
  private_class_method :build_user_message
end
