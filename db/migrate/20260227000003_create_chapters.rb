class CreateChapters < ActiveRecord::Migration[8.1]
  def change
    create_table :chapters do |t|
      t.bigint :game_id, null: false
      t.integer :number, null: false, default: 1
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :chapters, :game_id
    add_index :chapters, [ :game_id, :number ], unique: true
  end
end
