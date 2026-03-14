class CreateImpressions < ActiveRecord::Migration[8.1]
  def change
    enable_extension "vector"

    create_table :impressions do |t|
      t.references :game, null: false, foreign_key: true
      t.integer :turn_number, null: false
      t.string :subject_type, null: false
      t.string :subject_id
      t.text :fact, null: false
      t.vector :embedding, limit: 1536

      t.timestamps
    end

    add_index :impressions, [ :game_id, :subject_type, :subject_id ]
    add_index :impressions, [ :game_id, :turn_number ]
  end
end
