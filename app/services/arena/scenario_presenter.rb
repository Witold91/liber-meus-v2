module Arena
  class ScenarioPresenter
    include Presenters::BaseMethods

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

      scene_actors = build_scene_actors(actors, actor_states, scene_id)
      scene_objects = build_scene_objects(objects, object_states, scene_id)
      append_improvised_objects(scene_objects, improvised, scene_id)

      {
        scene: { id: scene["id"], name: scene["name"], description: scene["description"] },
        actors: scene_actors,
        objects: scene_objects,
        exits: scene["exits"] || [],
        inventory: player_inventory(world_state)
      }
    end
  end
end
