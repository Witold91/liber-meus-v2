module Arena
  class ScenarioPresenter
    def initialize(scenario_hash, act_number, world_state)
      @scenario = scenario_hash
      @act_number = act_number
      @world_state = world_state
    end

    def act
      acts = @scenario["acts"] || []
      acts.find { |a| a["number"] == @act_number } || acts.first
    end

    def scenes
      act["scenes"] || []
    end

    def actors
      act["actors"] || []
    end

    def objects
      act["objects"] || []
    end

    def conditions
      act["conditions"] || []
    end

    def events
      act["events"] || []
    end

    def turn_limit
      @scenario["turn_limit"] || 20
    end

    def scene_context_for(scene_id, world_state)
      scene = scenes.find { |s| s["id"] == scene_id }
      return nil unless scene

      actor_states  = world_state["actors"]  || {}
      object_states = world_state["objects"] || {}
      improvised    = world_state["improvised_objects"] || {}

      scene_actors = actors.select { |a| current_actor_scene(a, actor_states) == scene_id }
        .map do |a|
          statuses = Array(actor_states.dig(a["id"], "statuses") || [ actor_states.dig(a["id"], "status") || a["default_status"] ])
          { id: a["id"], name: a["name"], description: a["description"], statuses: statuses, status_options: a["status_options"] || [] }
        end

      scene_objects = objects.select { |o| current_object_scene(o, object_states) == scene_id }
        .map do |o|
          statuses = Array(object_states.dig(o["id"], "statuses") || [ object_states.dig(o["id"], "status") || o["default_status"] ])
          { id: o["id"], name: o["name"], statuses: statuses }
        end

      # Include improvised objects that are at this scene or carried (no scene set)
      improvised.each do |item_id, data|
        item_scene = data["scene"]
        next unless item_scene == scene_id || item_scene.nil?
        scene_objects << { id: item_id, name: item_id.gsub("_", " "), statuses: [ data["status"] || "acquired" ] }
      end

      {
        scene: { id: scene["id"], name: scene["name"], description: scene["description"] },
        actors: scene_actors,
        objects: scene_objects,
        exits: scene["exits"] || []
      }
    end

    def world_state_delta
      changes = []
      actor_states  = @world_state["actors"]  || {}
      object_states = @world_state["objects"] || {}

      actors.each do |actor|
        state          = actor_states[actor["id"]] || {}
        current_status = state["status"] || actor["default_status"]
        current_scene  = state["scene"]  || actor["scene"]

        status_changed = current_status != actor["default_status"]
        scene_changed  = current_scene  != actor["scene"]
        next unless status_changed || scene_changed

        changes << {
          type:   "actor",
          id:     actor["id"],
          name:   actor["name"],
          status: current_status,
          scene:  scene_changed ? current_scene : nil
        }
      end

      objects.each do |obj|
        state          = object_states[obj["id"]] || {}
        current_status = state["status"] || obj["default_status"]
        current_scene  = state["scene"]  || obj["scene"]

        status_changed = current_status != obj["default_status"]
        scene_changed  = current_scene  != obj["scene"]
        next unless status_changed || scene_changed

        changes << {
          type:   "object",
          id:     obj["id"],
          name:   obj["name"],
          status: current_status,
          scene:  scene_changed ? current_scene : nil
        }
      end

      changes
    end

    def adjacent_scene_ids(scene_id)
      scene = scenes.find { |s| s["id"] == scene_id }
      return [] unless scene
      (scene["exits"] || []).map { |e| e["to"] }
    end

    def exit_scene?(scene_id)
      scene = scenes.find { |s| s["id"] == scene_id }
      return false unless scene
      (scene["exits"] || []).any? { |e| e["arena_exit"] == true }
    end

    private

    def current_actor_scene(actor, actor_states)
      actor_states.dig(actor["id"], "scene") || actor["scene"]
    end

    def current_object_scene(object, object_states)
      object_states.dig(object["id"], "scene") || object["scene"]
    end
  end
end
