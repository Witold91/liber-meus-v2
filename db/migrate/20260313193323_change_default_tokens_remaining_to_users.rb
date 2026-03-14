class ChangeDefaultTokensRemainingToUsers < ActiveRecord::Migration[8.1]
  def up
    change_column_default :users, :tokens_remaining, 100_000
    User.where(tokens_remaining: 20_000).update_all(tokens_remaining: 100_000)
  end

  def down
    change_column_default :users, :tokens_remaining, 20_000
  end
end
