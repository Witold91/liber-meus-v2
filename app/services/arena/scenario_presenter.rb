module Arena
  class ScenarioPresenter
    def initialize(scenario_hash, chapter_number, world_state)
      @scenario = scenario_hash
      @chapter_number = chapter_number
      @world_state = world_state
    end

    def chapter
      chapters = @scenario["chapters"] || []
      chapters.find { |c| c["number"] == @chapter_number } || chapters.first
    end

    def stages
      chapter["stages"] || []
    end

    def actors
      chapter["actors"] || []
    end

    def objects
      chapter["objects"] || []
    end

    def conditions
      chapter["conditions"] || []
    end

    def events
      chapter["events"] || []
    end

    def turn_limit
      @scenario["turn_limit"] || 20
    end

    def stage_context_for(stage_id, world_state)
      stage = stages.find { |s| s["id"] == stage_id }
      return nil unless stage

      actor_states = world_state["actors"] || {}
      object_states = world_state["objects"] || {}

      stage_actors = actors.select { |a| current_actor_stage(a, actor_states) == stage_id }
        .map do |a|
          statuses = Array(actor_states.dig(a["id"], "statuses") || [ actor_states.dig(a["id"], "status") || a["default_status"] ])
          { id: a["id"], name: a["name"], description: a["description"], statuses: statuses }
        end

      stage_objects = objects.select { |o| current_object_stage(o, object_states) == stage_id }
        .map do |o|
          statuses = Array(object_states.dig(o["id"], "statuses") || [ object_states.dig(o["id"], "status") || o["default_status"] ])
          { id: o["id"], name: o["name"], statuses: statuses }
        end

      {
        stage: { id: stage["id"], name: stage["name"], description: stage["description"] },
        actors: stage_actors,
        objects: stage_objects,
        exits: stage["exits"] || [],
        player_inventory: world_state["player_inventory"] || {}
      }
    end

    def adjacent_stage_ids(stage_id)
      stage = stages.find { |s| s["id"] == stage_id }
      return [] unless stage
      (stage["exits"] || []).map { |e| e["to"] }
    end

    def exit_stage?(stage_id)
      stage = stages.find { |s| s["id"] == stage_id }
      return false unless stage
      (stage["exits"] || []).any? { |e| e["arena_exit"] == true }
    end

    private

    def current_actor_stage(actor, actor_states)
      actor_states.dig(actor["id"], "stage") || actor["stage"]
    end

    def current_object_stage(object, object_states)
      object_states.dig(object["id"], "stage") || object["stage"]
    end
  end
end
