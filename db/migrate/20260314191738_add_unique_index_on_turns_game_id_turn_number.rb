class AddUniqueIndexOnTurnsGameIdTurnNumber < ActiveRecord::Migration[8.1]
  def change
    remove_index :turns, [ :game_id, :turn_number ], name: "index_turns_on_game_id_and_turn_number"
    add_index :turns, [ :game_id, :turn_number ], unique: true, name: "index_turns_on_game_id_and_turn_number"
  end
end
