class RenameChaptersToActs < ActiveRecord::Migration[8.1]
  def change
    rename_table :chapters, :acts
    rename_column :turns, :chapter_id, :act_id
  end
end
