module RandomMode
  class WorldPresenter
    include Presenters::BaseMethods

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

      scene_actors = build_scene_actors(scene_def_actors, actor_states, scene_id)

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

      scene_objects = build_scene_objects(scene_def_objects, object_states, scene_id)

      # Also include objects from other scenes that have moved here
      objects.each do |o|
        next if scene_def_objects.any? { |so| so["id"] == o["id"] }
        next unless object_states.dig(o["id"], "scene") == scene_id

        statuses = Array(object_states.dig(o["id"], "status") || o["default_status"])
        scene_objects << { id: o["id"], name: o["name"], statuses: statuses }
      end

      append_improvised_objects(scene_objects, improvised, scene_id)

      {
        scene: { id: scene["id"], name: scene["name"], description: scene["description"] },
        actors: scene_actors,
        objects: scene_objects,
        nearby_scenes: nearby_scene_names,
        inventory: player_inventory(world_state)
      }
    end

    private

    def nearby_scenes
      recent_ids = (@world_state["recently_visited_scenes"] || []).last(5).to_set
      recent_ids << @player_scene
      @generated_scenes.values_at(*recent_ids).compact
    end

    def nearby_scene_names
      @generated_scenes.except(@player_scene).map { |id, s| { id: id, name: s["name"] } }
    end
  end
end
