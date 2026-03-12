class AddMemorySummaryToSaves < ActiveRecord::Migration[8.1]
  def change
    add_column :saves, :memory_summary, :text
  end
end
