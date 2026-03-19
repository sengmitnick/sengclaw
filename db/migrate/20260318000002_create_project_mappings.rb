class CreateProjectMappings < ActiveRecord::Migration[7.2]
  def change
    create_table :project_mappings do |t|
      # Which OpenClacky instance owns this mapping
      t.string :install_token, null: false

      # Linear side
      t.string :linear_project_id
      t.string :linear_team_id, null: false

      # Local side (absolute path on the user's machine)
      t.string :local_path, null: false

      # Human-readable name for display
      t.string :name

      t.timestamps
    end

    add_index :project_mappings, :install_token
    add_index :project_mappings, [ :install_token, :linear_team_id ], unique: true
  end
end
