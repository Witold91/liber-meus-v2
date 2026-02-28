class TurnPersistenceService
  def self.create!(game:, act:, content:, turn_number:, options_payload: {}, llm_memory: nil, resolution_tag: nil, option_selected: nil, tokens_used: 0)
    Turn.create!(
      game: game,
      act: act,
      content: content,
      turn_number: turn_number,
      options_payload: options_payload,
      llm_memory: llm_memory,
      resolution_tag: resolution_tag,
      option_selected: option_selected,
      tokens_used: tokens_used
    )
  end
end
