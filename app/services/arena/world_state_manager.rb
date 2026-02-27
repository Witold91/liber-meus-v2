module Arena
  class WorldStateManager
    def initialize(world_state)
      @world_state = world_state.deep_dup
    end

    def apply_stage_diff(diff, scenario:)
      presenter = ScenarioPresenter.new(scenario, @world_state["chapter_number"] || 1, @world_state)
      valid_stage_ids = presenter.stages.map { |s| s["id"] } + [ "offstage" ]
      valid_actor_ids = presenter.actors.map { |a| a["id"] }
      valid_object_ids = presenter.objects.map { |o| o["id"] }
      stage_ids_by_slug = build_slug_map(presenter.stages)
      actor_ids_by_slug = build_slug_map(presenter.actors)
      object_ids_by_slug = build_slug_map(presenter.objects)

      result = @world_state.deep_dup

      if (actor_updates = diff["actor_updates"])
        actor_updates.each do |actor_id, updates|
          resolved_actor_id = resolve_id(actor_id, valid_actor_ids, actor_ids_by_slug)
          next unless resolved_actor_id
          result["actors"] ||= {}
          result["actors"][resolved_actor_id] ||= {}
          actor_def = presenter.actors.find { |a| a["id"] == resolved_actor_id }
          if updates["status"]
            valid_statuses = actor_def&.dig("status_options") || []
            if valid_statuses.empty? || valid_statuses.include?(updates["status"])
              result["actors"][resolved_actor_id]["status"] = updates["status"]
            end
          end
          result["actors"][resolved_actor_id].merge!(updates.except("status")) if updates.key?("notes")
        end
      end

      if (object_updates = diff["object_updates"])
        object_updates.each do |object_id, updates|
          resolved_object_id = resolve_id(object_id, valid_object_ids, object_ids_by_slug)

          if resolved_object_id
            result["objects"] ||= {}
            result["objects"][resolved_object_id] ||= {}
            obj_def = presenter.objects.find { |o| o["id"] == resolved_object_id }
            if updates["status"]
              valid_statuses = obj_def&.dig("status_options") || []
              if valid_statuses.empty? || valid_statuses.include?(updates["status"])
                result["objects"][resolved_object_id]["status"] = updates["status"]
              end
            end
          else
            # Object not in scenario — treat as an improvised item the player acquired
            result["player_inventory"] ||= {}
            result["player_inventory"][object_id] = updates.slice("status").presence || { "status" => "acquired" }
          end
        end
      end

      if (actor_moved = diff["actor_moved_to"])
        actor_moved.each do |actor_id, stage_id|
          resolved_actor_id = resolve_id(actor_id, valid_actor_ids, actor_ids_by_slug)
          resolved_stage_id = resolve_id(stage_id, valid_stage_ids, stage_ids_by_slug)
          next unless resolved_actor_id
          next unless resolved_stage_id
          result["actors"] ||= {}
          result["actors"][resolved_actor_id] ||= {}
          result["actors"][resolved_actor_id]["stage"] = resolved_stage_id
        end
      end

      if (player_moved = diff["player_moved_to"])
        stage_id = resolve_id(player_moved, valid_stage_ids, stage_ids_by_slug)
        if stage_id
          result["player_stage"] = stage_id
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
