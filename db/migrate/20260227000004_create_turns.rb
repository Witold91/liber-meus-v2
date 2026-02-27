class CreateTurns < ActiveRecord::Migration[8.1]
  def change
    create_table :turns do |t|
      t.bigint :game_id, null: false
      t.bigint :chapter_id, null: false
      t.text :content
      t.jsonb :options_payload, null: false, default: {}
      t.string :option_selected
      t.string :resolution_tag
      t.text :llm_memory
      t.integer :turn_number, null: false, default: 0

      t.timestamps
    end

    add_index :turns, :game_id
    add_index :turns, :chapter_id
    add_index :turns, [ :game_id, :turn_number ]
  end
end
