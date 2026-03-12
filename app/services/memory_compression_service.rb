class MemoryCompressionService
  COMPRESSION_THRESHOLD = 10
  COMPRESS_COUNT = 5
  SYSTEM_PROMPT_PATH = Rails.root.join("lib", "prompts", "memory_compression.txt")

  def self.maybe_compress!(game)
    uncompressed_turns = game.turns
                             .where.not(llm_memory: [nil, ""])
                             .order(:turn_number)

    return false if uncompressed_turns.count < COMPRESSION_THRESHOLD

    # Compress only the oldest notes, keep the most recent ones intact
    oldest_turns = uncompressed_turns.limit(COMPRESS_COUNT)
    existing_summary = game.memory_summary
    notes = oldest_turns.map { |t| { turn_number: t.turn_number, note: t.llm_memory } }

    summary, _tokens = compress(existing_summary, notes)

    game.update!(memory_summary: summary)
    oldest_turns.update_all(llm_memory: nil)

    true
  end

  def self.compress(existing_summary, notes)
    system_prompt = File.read(SYSTEM_PROMPT_PATH)
    user_message = build_user_message(existing_summary, notes)

    result, tokens = AIClient.chat_json(
      system_prompt: system_prompt,
      user_message: user_message,
      model: AIClient.difficulty_model,
      temperature: 0.2,
      service_name: "MemoryCompressionService"
    )

    [result["summary"], tokens]
  end

  def self.build_user_message(existing_summary, notes)
    parts = []
    if existing_summary.present?
      parts << "PREVIOUS SUMMARY:"
      parts << existing_summary
      parts << ""
    end
    parts << "MEMORY NOTES TO COMPRESS:"
    notes.each do |n|
      parts << "  T#{n[:turn_number]} - #{n[:note]}"
    end
    parts.join("\n")
  end

  private_class_method :compress, :build_user_message
end
