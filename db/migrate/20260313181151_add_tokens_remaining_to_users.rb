class AddTokensRemainingToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :tokens_remaining, :integer, default: 20_000, null: false
    add_column :users, :deleted_at, :datetime
  end
end
