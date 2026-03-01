class AddWorldStateSnapshotToActs < ActiveRecord::Migration[8.0]
  def change
    add_column :acts, :world_state_snapshot, :jsonb, default: {}
  end
end
