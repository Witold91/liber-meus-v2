class DifficultyRatingService
  SYSTEM_PROMPT_PATH = Rails.root.join("lib", "prompts", "difficulty_rating.txt")
  FALLBACK = { "difficulty" => "medium" }.freeze

  def self.rate(action, stage_context, hero)
    client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))
    model = ENV.fetch("AI_DIFFICULTY_MODEL", "gpt-4o-mini")

    system_prompt = File.read(SYSTEM_PROMPT_PATH)
    user_message = build_user_message(action, stage_context, hero)

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
    [ FALLBACK.dup, 0 ]
  end

  def self.build_user_message(action, stage_context, hero)
    parts = []
    parts << I18n.t("services.difficulty_rating_service.prompt.hero", name: hero.name, description: hero.description)
    parts << ""
    parts << I18n.t("services.difficulty_rating_service.prompt.current_stage", stage_name: stage_context.dig(:stage, :name))
    parts << stage_context.dig(:stage, :description).to_s
    parts << ""

    if stage_context[:actors].any?
      parts << I18n.t("services.difficulty_rating_service.prompt.actors_present")
      stage_context[:actors].each do |a|
        parts << I18n.t("services.difficulty_rating_service.prompt.list_item", name: a[:name], statuses: a[:statuses].join(", "))
      end
      parts << ""
    end

    if stage_context[:objects].any?
      parts << I18n.t("services.difficulty_rating_service.prompt.objects_present")
      stage_context[:objects].each do |o|
        parts << I18n.t("services.difficulty_rating_service.prompt.list_item", name: o[:name], statuses: o[:statuses].join(", "))
      end
      parts << ""
    end

    parts << I18n.t("services.difficulty_rating_service.prompt.player_action", action: action)
    parts.join("\n")
  end
  private_class_method :build_user_message
end
