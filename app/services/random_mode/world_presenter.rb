module RandomMode
  class WorldPresenter
    def initialize(world_state)
      @world_state = world_state
      @generated_scenes = world_state["generated_scenes"] || {}
      @player_scene = world_state["player_scene"]
    end

    def scenes
      @generated_scenes.values
    end

    def actors
      nearby_scenes.flat_map { |s| s["actors"] || [] }
    end

    def objects
      nearby_scenes.flat_map { |s| s["objects"] || [] }
    end

    def scene_context_for(scene_id, world_state)
      scene = @generated_scenes[scene_id]
      return nil unless scene

      actor_states  = world_state["actors"]  || {}
      object_states = world_state["objects"] || {}
      improvised    = world_state["improvised_objects"] || {}

      scene_def_actors = scene["actors"] || []
      scene_def_objects = scene["objects"] || []

      scene_actors = scene_def_actors
        .select { |a| current_scene_for(a, actor_states) == scene_id }
        .map do |a|
          statuses = Array(actor_states.dig(a["id"], "status") || a["default_status"])
          {
            id: a["id"], name: a["name"], description: a["description"],
            statuses: statuses, status_options: a["status_options"] || []
          }
        end

      # Also include actors from other scenes that have moved here
      actors.each do |a|
        next if scene_def_actors.any? { |sa| sa["id"] == a["id"] }
        next unless actor_states.dig(a["id"], "scene") == scene_id

        statuses = Array(actor_states.dig(a["id"], "status") || a["default_status"])
        scene_actors << {
          id: a["id"], name: a["name"], description: a["description"],
          statuses: statuses, status_options: a["status_options"] || []
        }
      end

      scene_objects = scene_def_objects
        .select { |o| current_scene_for(o, object_states) == scene_id }
        .map do |o|
          statuses = Array(object_states.dig(o["id"], "status") || o["default_status"])
          { id: o["id"], name: o["name"], statuses: statuses }
        end

      # Also include objects from other scenes that have moved here
      objects.each do |o|
        next if scene_def_objects.any? { |so| so["id"] == o["id"] }
        next unless object_states.dig(o["id"], "scene") == scene_id

        statuses = Array(object_states.dig(o["id"], "status") || o["default_status"])
        scene_objects << { id: o["id"], name: o["name"], statuses: statuses }
      end

      # Improvised objects at this scene
      improvised.each do |item_id, data|
        next unless data["scene"] == scene_id
        scene_objects << { id: item_id, name: item_id.gsub("_", " "), statuses: [ data["status"] || "acquired" ] }
      end

      {
        scene: { id: scene["id"], name: scene["name"], description: scene["description"] },
        actors: scene_actors,
        objects: scene_objects,
        nearby_scenes: nearby_scene_names,
        inventory: player_inventory(world_state)
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

    private

    def player_inventory(world_state)
      object_states = world_state["objects"] || {}
      improvised    = world_state["improvised_objects"] || {}
      items = []

      objects.each do |obj|
        state = object_states[obj["id"]] || {}
        next unless state["scene"] == "player_inventory"
        statuses = Array(state["status"] || obj["default_status"])
        items << { id: obj["id"], name: obj["name"], statuses: statuses }
      end

      improvised.each do |item_id, data|
        next unless data["scene"].nil? || data["scene"] == "player_inventory"
        items << { id: item_id, name: item_id.gsub("_", " "), statuses: [ data["status"] || "acquired" ] }
      end

      items
    end

    def nearby_scenes
      recent_ids = (@world_state["recently_visited_scenes"] || []).last(5).to_set
      recent_ids << @player_scene
      @generated_scenes.values_at(*recent_ids).compact
    end

    def nearby_scene_names
      @generated_scenes.except(@player_scene).map { |id, s| { id: id, name: s["name"] } }
    end

    def current_scene_for(entity, states)
      states.dig(entity["id"], "scene") || entity["scene"]
    end
  end
end
