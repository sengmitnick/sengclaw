class CreateLinearInstallations < ActiveRecord::Migration[7.2]
  def change
    create_table :linear_installations do |t|
      # OpenClacky instance identity (UUID generated locally)
      t.string :install_token, null: false, index: { unique: true }

      # Linear workspace info
      t.string :workspace_id, null: false
      t.string :linear_actor_id  # viewer.id from Linear (app's user ID in this workspace)

      # OAuth tokens
      t.text :access_token, null: false
      t.text :refresh_token
      t.datetime :expires_at

      t.timestamps
    end

    add_index :linear_installations, :workspace_id
  end
end
