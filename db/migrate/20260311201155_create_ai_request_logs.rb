class CreateAIRequestLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_request_logs do |t|
      t.string :service_name, null: false
      t.string :model, null: false
      t.float :temperature
      t.jsonb :messages, default: [], null: false
      t.jsonb :response_body, default: {}
      t.integer :tokens_used, default: 0
      t.integer :duration_ms, default: 0
      t.string :error_message
      t.timestamps
    end

    add_index :ai_request_logs, :service_name
    add_index :ai_request_logs, :created_at
  end
end
