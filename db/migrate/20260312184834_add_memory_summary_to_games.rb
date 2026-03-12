class AddMemorySummaryToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :memory_summary, :text
  end
end
