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

      result = @world_state.deep_dup

      if (actor_updates = diff["actor_updates"])
        actor_updates.each do |actor_id, updates|
          next unless valid_actor_ids.include?(actor_id)
          result["actors"] ||= {}
          result["actors"][actor_id] ||= {}
          actor_def = presenter.actors.find { |a| a["id"] == actor_id }
          if updates["status"]
            valid_statuses = actor_def&.dig("status_options") || []
            if valid_statuses.empty? || valid_statuses.include?(updates["status"])
              result["actors"][actor_id]["status"] = updates["status"]
            end
          end
          result["actors"][actor_id].merge!(updates.except("status")) if updates.key?("notes")
        end
      end

      if (object_updates = diff["object_updates"])
        object_updates.each do |object_id, updates|
          next unless valid_object_ids.include?(object_id)
          result["objects"] ||= {}
          result["objects"][object_id] ||= {}
          obj_def = presenter.objects.find { |o| o["id"] == object_id }
          if updates["status"]
            valid_statuses = obj_def&.dig("status_options") || []
            if valid_statuses.empty? || valid_statuses.include?(updates["status"])
              result["objects"][object_id]["status"] = updates["status"]
            end
          end
        end
      end

      if (actor_moved = diff["actor_moved_to"])
        actor_moved.each do |actor_id, stage_id|
          next unless valid_actor_ids.include?(actor_id)
          next unless valid_stage_ids.include?(stage_id)
          result["actors"] ||= {}
          result["actors"][actor_id] ||= {}
          result["actors"][actor_id]["stage"] = stage_id
        end
      end

      if (player_moved = diff["player_moved_to"])
        stage_id = player_moved.is_a?(String) ? player_moved : player_moved.to_s
        if valid_stage_ids.include?(stage_id)
          result["player_stage"] = stage_id
        end
      end

      result
    end
  end
end
