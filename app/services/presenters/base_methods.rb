module Presenters
  module BaseMethods
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

    def build_scene_actors(actors_list, actor_states, scene_id)
      actors_list.select { |a| current_entity_scene(a, actor_states) == scene_id }
        .map do |a|
          statuses = Array(actor_states.dig(a["id"], "statuses") || [ actor_states.dig(a["id"], "status") || a["default_status"] ])
          disposition = actor_states.dig(a["id"], "disposition") || a["default_disposition"] || "neutral"
          { id: a["id"], name: a["name"], description: a["description"], statuses: statuses, status_options: a["status_options"] || [], disposition: disposition }
        end
    end

    def build_scene_objects(objects_list, object_states, scene_id)
      objects_list.select { |o| current_entity_scene(o, object_states) == scene_id }
        .map do |o|
          statuses = Array(object_states.dig(o["id"], "statuses") || [ object_states.dig(o["id"], "status") || o["default_status"] ])
          { id: o["id"], name: o["name"], description: o.key?("description") ? o["description"] : nil, statuses: statuses }.compact
        end
    end

    def append_improvised_objects(scene_objects, improvised, scene_id)
      improvised.each do |item_id, data|
        next unless data["scene"] == scene_id
        scene_objects << { id: item_id, name: item_id.gsub("_", " "), statuses: [ data["status"] || "acquired" ] }
      end
    end

    def current_entity_scene(entity, states)
      states.dig(entity["id"], "scene") || entity["scene"]
    end
  end
end
