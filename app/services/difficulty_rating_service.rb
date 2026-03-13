class DifficultyRatingService
  SYSTEM_PROMPT_PATH = Rails.root.join("lib", "prompts", "difficulty_rating.txt")

  def self.rate(action, scene_context, hero, recent_actions = [], world_context: nil, memory_summary: nil, memory_notes: [], current_hp: nil, established_facts: [])
    system_prompt = File.read(SYSTEM_PROMPT_PATH)
    system_prompt += "\n\nWORLD CONTEXT:\n#{world_context.strip}" if world_context.present?

    AIClient.chat_json(
      system_prompt: system_prompt,
      user_message: build_user_message(action, scene_context, hero, recent_actions, memory_summary: memory_summary, memory_notes: memory_notes, current_hp: current_hp, established_facts: established_facts),
      model: AIClient.difficulty_model,
      temperature: 0.2,
      service_name: "DifficultyRatingService"
    )
  end

  def self.build_user_message(action, scene_context, hero, recent_actions = [], memory_summary: nil, memory_notes: [], current_hp: nil, established_facts: [])
    parts = []
    parts << I18n.t("services.difficulty_rating_service.prompt.hero", name: hero.name, description: hero.llm_description || hero.description)
    if current_hp
      parts << I18n.t("services.arena_narrator_service.prompt.player_hp", current: current_hp, max: OutcomeResolutionService::BASE_HEALTH)
    end
    parts << ""
    parts << I18n.t("services.difficulty_rating_service.prompt.current_scene", scene_name: scene_context.dig(:scene, :name))
    parts << scene_context.dig(:scene, :description).to_s
    parts << ""

    if scene_context[:actors].any?
      parts << I18n.t("services.difficulty_rating_service.prompt.actors_present")
      scene_context[:actors].each do |a|
        line = I18n.t("services.difficulty_rating_service.prompt.list_item", name: a[:name], statuses: a[:statuses].join(", "))
        line += " | disposition: #{a[:disposition]}" if a[:disposition].present?
        parts << line
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

    inventory = scene_context[:inventory] || []
    if inventory.any?
      parts << I18n.t("services.difficulty_rating_service.prompt.inventory_header", default: "PLAYER INVENTORY:")
      inventory.each do |item|
        parts << I18n.t("services.difficulty_rating_service.prompt.list_item", name: item[:name], statuses: item[:statuses].join(", "))
      end
      parts << ""
    end

    if scene_context[:exits].any?
      exits_str = scene_context[:exits].map { |e| e["label"] }.join(", ")
      parts << I18n.t("services.difficulty_rating_service.prompt.exits", exits: exits_str)
      parts << ""
    end

    if memory_summary.present? || memory_notes.any?
      parts << I18n.t("services.difficulty_rating_service.prompt.story_context_header", default: "STORY CONTEXT:")
      if memory_summary.present?
        parts << "  #{memory_summary}"
      end
      memory_notes.each do |note|
        parts << "  T#{note[:turn_number]} - #{note[:note]}"
      end
      parts << ""
    end

    if established_facts.any?
      parts << I18n.t("services.difficulty_rating_service.prompt.established_facts_header", default: "ESTABLISHED FACTS:")
      established_facts.each { |fact| parts << "  - #{fact}" }
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
