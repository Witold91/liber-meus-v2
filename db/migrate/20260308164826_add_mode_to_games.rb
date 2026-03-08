class AddModeToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :mode, :string, default: "scenario", null: false
  end
end
