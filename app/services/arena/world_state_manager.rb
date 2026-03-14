module Arena
  class WorldStateManager
    def initialize(world_state)
      @world_state = world_state.deep_dup
    end

    def apply_scene_diff(diff, scenario: nil, presenter: nil)
      presenter ||= ScenarioPresenter.new(scenario, @world_state["act_number"] || 1, @world_state)
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

          if resolved_actor_id
            result["actors"] ||= {}
            result["actors"][resolved_actor_id] ||= {}
            result["actors"][resolved_actor_id]["status"] = updates["status"] if updates["status"]
            result["actors"][resolved_actor_id].merge!(updates.except("status")) if updates.key?("notes")
          elsif updates["new_actor"]
            # New actor introduced by the narrator (random mode)
            normalized_id = normalize_slug(actor_id)
            result["actors"] ||= {}
            result["actors"][normalized_id] = {
              "scene" => updates["scene"] || result["player_scene"],
              "status" => updates["status"] || "present"
            }
            register_new_actor(result, normalized_id, updates)
          end
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
            normalized_id = normalize_slug(object_id)
            result["improvised_objects"] ||= {}
            result["improvised_objects"][normalized_id] = updates.slice("status", "scene").presence || { "status" => "acquired" }
          end
        end
      end

      if (disposition_updates = diff["disposition_updates"])
        disposition_updates.each do |actor_id, disposition|
          resolved_actor_id = resolve_id(actor_id, valid_actor_ids, actor_ids_by_slug) || known_actor_id(result, actor_id)
          next unless resolved_actor_id
          result["actors"] ||= {}
          result["actors"][resolved_actor_id] ||= {}
          result["actors"][resolved_actor_id]["disposition"] = disposition.to_s
        end
      end

      if (actor_moved = diff["actor_moved_to"])
        actor_moved.each do |actor_id, scene_id|
          resolved_actor_id = resolve_id(actor_id, valid_actor_ids, actor_ids_by_slug) || known_actor_id(result, actor_id)
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
        # In random mode, accept any scene ID (new scenes are generated on-the-fly)
        scene_id ||= normalize_slug(player_moved) if presenter.is_a?(RandomMode::WorldPresenter)
        result["player_scene"] = scene_id if scene_id
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

    def known_actor_id(state, actor_id)
      (state["actors"] || {}).key?(actor_id) ? actor_id : nil
    end

    def register_new_actor(state, actor_id, updates)
      scene_id = updates["scene"] || state["player_scene"]
      return unless scene_id

      scene_def = (state["generated_scenes"] || {})[scene_id]
      return unless scene_def

      scene_def["actors"] ||= []
      return if scene_def["actors"].any? { |a| a["id"] == actor_id }

      scene_def["actors"] << {
        "id" => actor_id,
        "name" => updates["name"] || actor_id.tr("_", " ").titleize,
        "description" => updates["description"],
        "scene" => scene_id,
        "default_status" => updates["status"] || "present"
      }
    end
  end
end
