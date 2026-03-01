class CreateSaves < ActiveRecord::Migration[8.1]
  def change
    create_table :saves do |t|
      t.references :game, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.jsonb      :world_state, null: false, default: {}
      t.integer    :act_number, null: false
      t.integer    :turn_number, null: false
      t.bigint     :hero_id, null: false
      t.string     :label, null: false

      t.timestamps
    end

    add_index :saves, [:game_id, :created_at]
    add_foreign_key :saves, :heroes
  end
end
