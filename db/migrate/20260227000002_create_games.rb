class CreateGames < ActiveRecord::Migration[8.1]
  def change
    create_table :games do |t|
      t.bigint :hero_id, null: false
      t.string :scenario_slug
      t.jsonb :world_state, null: false, default: {}
      t.string :game_language, null: false, default: "en"
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :games, :hero_id
    add_index :games, :status
  end
end
