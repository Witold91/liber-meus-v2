class AddTokensUsedToTurns < ActiveRecord::Migration[8.1]
  def change
    add_column :turns, :tokens_used, :integer, default: 0, null: false
  end
end
