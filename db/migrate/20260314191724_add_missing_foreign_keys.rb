class AddMissingForeignKeys < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :acts, :games
    add_foreign_key :turns, :games
    add_foreign_key :turns, :acts
    add_foreign_key :games, :heroes
  end
end
