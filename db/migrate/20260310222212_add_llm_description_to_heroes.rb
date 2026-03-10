class AddLlmDescriptionToHeroes < ActiveRecord::Migration[8.1]
  def change
    add_column :heroes, :llm_description, :text
  end
end
