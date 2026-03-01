class AddUserIdToGames < ActiveRecord::Migration[8.1]
  def change
    add_reference :games, :user, null: true, foreign_key: true
  end
end
