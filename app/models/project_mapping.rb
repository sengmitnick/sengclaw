class ProjectMapping < ApplicationRecord
  validates :install_token, presence: true
  validates :linear_team_id, presence: true
  validates :local_path, presence: true
  validates :linear_team_id, uniqueness: { scope: :install_token }

  # Find the mapping for a given workspace webhook event
  # Tries project-level first, falls back to team-level
  def self.resolve(install_token:, linear_team_id:, linear_project_id: nil)
    if linear_project_id.present?
      find_by(install_token:, linear_project_id:) ||
        find_by(install_token:, linear_team_id:)
    else
      find_by(install_token:, linear_team_id:)
    end
  end
end
