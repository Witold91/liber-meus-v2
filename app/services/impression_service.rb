class ImpressionService
  DETERMINISTIC_LIMIT = 5
  SEMANTIC_LIMIT = 5
  MAX_RESULTS = 10
  SEMANTIC_DISTANCE_THRESHOLD = 0.45

  def self.store!(game:, turn_number:, impressions_data:, memory_note: nil)
    records = Array(impressions_data).filter_map do |imp|
      next unless imp.is_a?(Hash) && imp["fact"].present?

      {
        subject_type: imp["type"].to_s,
        subject_id: imp["subject"].presence,
        fact: imp["fact"]
      }
    end

    if memory_note.present?
      records << { subject_type: "memory", subject_id: nil, fact: memory_note }
    end

    return if records.empty?

    facts = records.map { |r| r[:fact] }
    embeddings = EmbeddingService.embed(facts)

    records.each_with_index do |record, i|
      game.impressions.create!(
        turn_number: turn_number,
        subject_type: record[:subject_type],
        subject_id: record[:subject_id],
        fact: record[:fact],
        embedding: embeddings[i]
      )
    end
  rescue => e
    Rails.logger.error("[ImpressionService] store! failed: #{e.message}")
  end

  def self.retrieve(game:, scene_id:, actor_ids:, action_text:)
    # 1. Deterministic: impressions for current scene + present actors
    subject_ids = [ scene_id, *Array(actor_ids) ].compact.uniq
    deterministic = game.impressions
      .where(subject_type: %w[actor scene])
      .where(subject_id: subject_ids)
      .order(turn_number: :desc)
      .limit(DETERMINISTIC_LIMIT)
      .to_a

    # 2. Semantic: nearest neighbors to action_text
    semantic = []
    if action_text.present?
      query_embedding = EmbeddingService.embed_single(action_text)
      if query_embedding
        deterministic_ids = deterministic.map(&:id)
        scope = game.impressions
          .where.not(subject_type: "memory")
        scope = scope.where.not(id: deterministic_ids) if deterministic_ids.any?

        semantic = scope
          .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
          .limit(SEMANTIC_LIMIT)
          .to_a
          .select { |imp| imp.neighbor_distance <= SEMANTIC_DISTANCE_THRESHOLD }
      end
    end

    (deterministic + semantic)
      .uniq(&:id)
      .first(MAX_RESULTS)
      .map { |imp| imp.subject_id.present? ? "[#{imp.subject_id}] #{imp.fact}" : imp.fact }
  rescue => e
    Rails.logger.error("[ImpressionService] retrieve failed: #{e.message}")
    []
  end
end
