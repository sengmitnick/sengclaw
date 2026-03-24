class FixProjectMappingsUniqueIndex < ActiveRecord::Migration[7.2]
  def change
    # Remove the old unique index that only allows one mapping per (install_token, team)
    # This was too restrictive — one install_token can have multiple projects under the same team
    remove_index :project_mappings, name: "index_project_mappings_on_install_token_and_linear_team_id"

    # Team-level mapping: one default path per (install_token, team) when linear_project_id is null
    add_index :project_mappings,
              [ :install_token, :linear_team_id ],
              unique: true,
              where: "linear_project_id IS NULL",
              name: "index_project_mappings_team_level"

    # Project-level mapping: one path per (install_token, project) — more specific
    add_index :project_mappings,
              [ :install_token, :linear_project_id ],
              unique: true,
              where: "linear_project_id IS NOT NULL",
              name: "index_project_mappings_project_level"
  end
end
