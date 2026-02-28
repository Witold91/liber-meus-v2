module Arena
  class WorldStateManager
    def initialize(world_state)
      @world_state = world_state.deep_dup
    end

    def apply_scene_diff(diff, scenario:)
      presenter = ScenarioPresenter.new(scenario, @world_state["act_number"] || 1, @world_state)
      valid_scene_ids = presenter.scenes.map { |s| s["id"] } + [ "offstage" ]
      valid_actor_ids = presenter.actors.map { |a| a["id"] }
      valid_object_ids = presenter.objects.map { |o| o["id"] }
      scene_ids_by_slug = build_slug_map(presenter.scenes)
      actor_ids_by_slug = build_slug_map(presenter.actors)
      object_ids_by_slug = build_slug_map(presenter.objects)

      result = @world_state.deep_dup

      if (actor_updates = diff["actor_updates"])
        actor_updates.each do |actor_id, updates|
          resolved_actor_id = resolve_id(actor_id, valid_actor_ids, actor_ids_by_slug)
          next unless resolved_actor_id
          result["actors"] ||= {}
          result["actors"][resolved_actor_id] ||= {}
          result["actors"][resolved_actor_id]["status"] = updates["status"] if updates["status"]
          result["actors"][resolved_actor_id].merge!(updates.except("status")) if updates.key?("notes")
        end
      end

      if (object_updates = diff["object_updates"])
        object_updates.each do |object_id, updates|
          resolved_object_id = resolve_id(object_id, valid_object_ids, object_ids_by_slug)

          if resolved_object_id
            result["objects"] ||= {}
            result["objects"][resolved_object_id] ||= {}
            result["objects"][resolved_object_id]["status"] = updates["status"] if updates["status"]
            result["objects"][resolved_object_id]["scene"] = updates["scene"] if updates.key?("scene")
          else
            # Object not in scenario — treat as an improvised item (may be scene-bound or carried)
            result["improvised_objects"] ||= {}
            result["improvised_objects"][object_id] = updates.slice("status", "scene").presence || { "status" => "acquired" }
          end
        end
      end

      if (actor_moved = diff["actor_moved_to"])
        actor_moved.each do |actor_id, scene_id|
          resolved_actor_id = resolve_id(actor_id, valid_actor_ids, actor_ids_by_slug)
          resolved_scene_id = resolve_id(scene_id, valid_scene_ids, scene_ids_by_slug)
          next unless resolved_actor_id
          next unless resolved_scene_id
          result["actors"] ||= {}
          result["actors"][resolved_actor_id] ||= {}
          result["actors"][resolved_actor_id]["scene"] = resolved_scene_id
        end
      end

      if (player_moved = diff["player_moved_to"])
        scene_id = resolve_id(player_moved, valid_scene_ids, scene_ids_by_slug)
        if scene_id && presenter.adjacent_scene_ids(result["player_scene"]).include?(scene_id)
          result["player_scene"] = scene_id
        end
      end

      result
    end

    private

    def resolve_id(candidate, valid_ids, ids_by_slug)
      value = candidate.to_s
      return value if valid_ids.include?(value)

      ids_by_slug[normalize_slug(value)]
    end

    def build_slug_map(definitions)
      definitions.each_with_object({}) do |item, map|
        slug = normalize_slug(item["name"])
        map[slug] ||= item["id"] if slug.present? && item["id"].present?
      end
    end

    def normalize_slug(value)
      value.to_s.parameterize(separator: "_")
    end
  end
end
