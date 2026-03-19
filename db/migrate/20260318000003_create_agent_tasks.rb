class CreateAgentTasks < ActiveRecord::Migration[7.2]
  def change
    create_table :agent_tasks do |t|
      # Linear identifiers
      t.string :agent_session_id, null: false, index: { unique: true }
      t.string :issue_id, null: false
      t.string :workspace_id, null: false

      # Which OpenClacky handles this task
      t.string :install_token, null: false

      # Lifecycle: pending → dispatched → running → done | failed | timeout
      t.string :status, null: false, default: "pending"

      # Raw webhook payload (for replay/debug)
      t.text :webhook_payload

      # Error info when failed
      t.text :error_message

      t.timestamps
    end

    add_index :agent_tasks, :install_token
    add_index :agent_tasks, :status
    add_index :agent_tasks, :workspace_id
  end
end
