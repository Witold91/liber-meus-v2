class CreateHeroes < ActiveRecord::Migration[8.1]
  def change
    create_table :heroes do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.text :description
      t.string :sex

      t.timestamps
    end

    add_index :heroes, :slug, unique: true
  end
end
