class ArenaNarratorService
  SYSTEM_PROMPT_PATH = Rails.root.join("lib", "prompts", "arena_narrator.txt")
  EPILOGUE_PROMPT_PATH = Rails.root.join("lib", "prompts", "arena_epilogue.txt")
  PROLOGUE_PROMPT_PATH = Rails.root.join("lib", "prompts", "arena_prologue.txt")

  def self.narrate(action, resolution_tag, difficulty, scene_context, turn_context, health_loss = 0, world_context: nil, narrator_style: nil, event_descriptions: [], prompt_path: nil, stream: nil, hero: nil, turn_number: nil, random_mode: false, encountered_actors: [], current_hp: nil, health_gain: 0)
    model = AIClient.narrator_model

    system_prompt = File.read(prompt_path || SYSTEM_PROMPT_PATH)
    system_prompt += "\n\nWORLD CONTEXT:\n#{world_context.strip}" if world_context.present?
    system_prompt += "\n\nSTYLE DIRECTIVE:\n#{narrator_style.strip}" if narrator_style.present?
    user_message = build_user_message(action, resolution_tag, difficulty, scene_context, turn_context, health_loss, event_descriptions, hero: hero, turn_number: turn_number, random_mode: random_mode, encountered_actors: encountered_actors, current_hp: current_hp, health_gain: health_gain)

    if stream
      narrate_streaming(model, system_prompt, user_message, stream)
    else
      narrate_blocking(model, system_prompt, user_message)
    end
  rescue => e
    Rails.logger.error("[ArenaNarratorService] Error: #{e.message}")
    raise AIConnectionError, e.message
  end

  def self.narrate_blocking(model, system_prompt, user_message)
    AIClient.chat_json(
      system_prompt: system_prompt,
      user_message: user_message,
      model: model,
      temperature: 0.7,
      service_name: "ArenaNarratorService"
    )
  end
  private_class_method :narrate_blocking

  def self.narrate_streaming(model, system_prompt, user_message, on_chunk)
    buffer = +""
    narrative_buffer = +""
    in_narrative = false
    narrative_done = false
    escape_next = false
    tokens_used = 0

    stream_proc = proc do |chunk, _bytesize|
      delta = chunk.dig("choices", 0, "delta", "content")
      if (usage = chunk.dig("usage", "total_tokens"))
        tokens_used = usage.to_i
      end
      next unless delta

      buffer << delta

      if narrative_done
        # Already finished streaming narrative — skip
      elsif in_narrative
        # Track each char to detect the closing quote of the narrative value.
        # Escaped quotes (\") are skipped via escape_next.
        send_up_to = delta.length
        delta.each_char.with_index do |c, i|
          if escape_next
            escape_next = false
          elsif c == '\\'
            escape_next = true
          elsif c == '"'
            send_up_to = i
            in_narrative = false
            narrative_done = true
            break
          end
        end
        part = delta[0...send_up_to]
        unless part.empty?
          narrative_buffer << part
          on_chunk.call(part)
        end
      elsif buffer.match?(/"narrative"\s*:\s*"/)
        # We just entered the narrative value — extract any content after the opening quote
        in_narrative = true
        if (match = buffer.match(/"narrative"\s*:\s*"([^"]*)$/))
          initial = match[1]
          unless initial.empty?
            narrative_buffer << initial
            on_chunk.call(initial)
          end
        end
      end
    end

    parameters = {
      model: model,
      temperature: 0.7,
      stream: stream_proc,
      stream_options: { include_usage: true },
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: user_message }
      ]
    }.merge(AIClient.json_response_format)

    _response, log = AIClient.chat_streaming(parameters: parameters, service_name: "ArenaNarratorService.streaming")

    parsed = begin
      AIClient.parse_json(buffer)
    rescue JSON::ParserError => e
      Rails.logger.warn("[ArenaNarratorService] JSON parse failed, using streamed narrative fallback: #{e.message}")
      # Unescape JSON string escapes from the raw narrative buffer
      fallback_narrative = narrative_buffer
        .gsub('\n', "\n").gsub('\t', "\t")
        .gsub('\\\\', "\\").gsub('\\"', '"')
      { "narrative" => fallback_narrative, "diff" => {}, "memory_note" => nil }
    end
    AIClient.complete_streaming_log(log, response_body: parsed, tokens: tokens_used)

    [ parsed, tokens_used ]
  end
  private_class_method :narrate_streaming

  def self.narrate_epilogue(scene_context, action, resolution_tag, ending_narrative, world_context: nil, narrator_style: nil)
    model = AIClient.narrator_model

    system_prompt = File.read(EPILOGUE_PROMPT_PATH)
    system_prompt += "\n\nWORLD CONTEXT:\n#{world_context.strip}" if world_context.present?
    system_prompt += "\n\nSTYLE DIRECTIVE:\n#{narrator_style.strip}" if narrator_style.present?

    localized_resolution = I18n.t("game.resolution_tags.#{resolution_tag}", default: resolution_tag).upcase
    user_message = I18n.t("services.arena_narrator_service.epilogue.intro",
                          action: action, resolution: localized_resolution,
                          scene_name: scene_context.dig(:scene, :name),
                          ending_narrative: ending_narrative)

    AIClient.chat_json(
      system_prompt: system_prompt,
      user_message: user_message,
      model: model,
      temperature: 0.7,
      service_name: "ArenaNarratorService.epilogue"
    )
  end

  def self.narrate_prologue(scene_context, act_intro, world_context: nil, narrator_style: nil)
    model = AIClient.narrator_model

    system_prompt = File.read(PROLOGUE_PROMPT_PATH)
    system_prompt += "\n\nWORLD CONTEXT:\n#{world_context.strip}" if world_context.present?
    system_prompt += "\n\nSTYLE DIRECTIVE:\n#{narrator_style.strip}" if narrator_style.present?

    user_message = I18n.t("services.arena_narrator_service.prologue.intro",
                          act_intro: act_intro,
                          scene_name: scene_context.dig(:scene, :name),
                          scene_description: scene_context.dig(:scene, :description).to_s)

    AIClient.chat_json(
      system_prompt: system_prompt,
      user_message: user_message,
      model: model,
      temperature: 0.7,
      service_name: "ArenaNarratorService.prologue"
    )
  end

  HERO_FULL_DESCRIPTION_TURNS = 3

  def self.build_user_message(action, resolution_tag, difficulty, scene_context, turn_context, health_loss = 0, event_descriptions = [], hero: nil, turn_number: nil, random_mode: false, encountered_actors: [], current_hp: nil, health_gain: 0)
    parts = []

    if hero
      compact = turn_number.present? && turn_number > HERO_FULL_DESCRIPTION_TURNS && hero.llm_description.present?
      description = compact ? hero.llm_description : (hero.description || hero.llm_description)
      parts << I18n.t("services.arena_narrator_service.prompt.protagonist", name: hero.name, description: description)
    end

    if current_hp
      parts << I18n.t("services.arena_narrator_service.prompt.player_hp", current: current_hp, max: OutcomeResolutionService::BASE_HEALTH)
    end

    parts << "" if hero || current_hp

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
        known = encountered_actors.include?(a[:id])
        parts << format_actor(a, known: known, show_status_options: !random_mode)
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

    inventory = scene_context[:inventory] || []
    if inventory.any?
      parts << I18n.t("services.arena_narrator_service.prompt.inventory_header")
      inventory.each do |item|
        parts << I18n.t(
          "services.arena_narrator_service.prompt.inventory_item",
          id: item[:id],
          name: item[:name],
          statuses: item[:statuses].join(", ")
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

    # Filter delta to only show entries NOT already visible in current scene actors/objects/inventory
    visible_ids = Set.new
    scene_context[:actors].each { |a| visible_ids << a[:id] }
    scene_context[:objects].each { |o| visible_ids << o[:id] }
    (scene_context[:inventory] || []).each { |i| visible_ids << i[:id] }

    delta = (turn_context[:world_state_delta] || []).reject { |d| visible_ids.include?(d[:id]) }
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

    memory_summary = turn_context[:memory_summary]
    memory_notes = turn_context[:memory_notes] || []
    if memory_summary.present? || memory_notes.any?
      parts << I18n.t("services.arena_narrator_service.prompt.story_so_far_header")
      if memory_summary.present?
        parts << I18n.t("services.arena_narrator_service.prompt.memory_summary_item", summary: memory_summary)
      end
      memory_notes.each do |note|
        parts << I18n.t("services.arena_narrator_service.prompt.memory_note_item", turn_number: note[:turn_number], note: note[:note])
      end
      parts << ""
    end

    established_facts = turn_context[:established_facts] || []
    if established_facts.any?
      parts << I18n.t("services.arena_narrator_service.prompt.established_facts_header")
      established_facts.each { |fact| parts << "  - #{fact}" }
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

    if health_gain > 0
      parts << I18n.t("services.arena_narrator_service.prompt.health_gain", amount: health_gain)
      parts << ""
    end

    if event_descriptions&.any?
      parts << "WORLD EVENTS THIS TURN:"
      event_descriptions.each { |d| parts << "- #{d}" }
      parts << ""
    end

    if (tail = turn_context[:previous_narrative_tail])
      parts << I18n.t("services.arena_narrator_service.prompt.previous_narrative_header")
      parts << tail.strip
      parts << ""
    end

    parts << I18n.t("services.arena_narrator_service.prompt.player_action", action: action)
    parts.join("\n")
  end
  private_class_method :build_user_message

  def self.format_actor(actor, known:, show_status_options:)
    line = "  - #{actor[:name]} [id=#{actor[:id]}]"
    line += " (#{actor[:description]})" unless known || actor[:description].blank?
    line += ": #{actor[:statuses].join(', ')}"
    disposition_label = I18n.t("services.arena_narrator_service.prompt.actor_disposition")
    line += " | #{disposition_label}: #{actor[:disposition]}" if actor[:disposition].present?
    if show_status_options && actor[:status_options]&.any?
      label = I18n.t("services.arena_narrator_service.prompt.actor_plot_statuses")
      line += " [#{label}: #{actor[:status_options].join(', ')}]"
    end
    line
  end
  private_class_method :format_actor
end
