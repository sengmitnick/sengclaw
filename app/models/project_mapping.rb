class ProjectMapping < ApplicationRecord
  validates :install_token, presence: true
  validates :linear_team_id, presence: true
  validates :local_path, presence: true

  # Team-level mapping: unique per (install_token, team) when no project is specified
  validates :linear_team_id,
            uniqueness: { scope: :install_token, message: "team-level mapping already exists for this install_token" },
            if: -> { linear_project_id.blank? }

  # Project-level mapping: unique per (install_token, project)
  validates :linear_project_id,
            uniqueness: { scope: :install_token, message: "project-level mapping already exists for this install_token" },
            if: -> { linear_project_id.present? }

  # Resolve which local path to use for an incoming Linear issue.
  #
  # Priority:
  #   1. Project-level mapping (install_token + linear_project_id) — most specific
  #   2. Team-level mapping   (install_token + linear_team_id)     — fallback default
  #
  # Returns a ProjectMapping or nil.
  def self.resolve(install_token:, linear_team_id:, linear_project_id: nil)
    if linear_project_id.present?
      find_by(install_token:, linear_project_id:) ||
        find_by(install_token:, linear_team_id:, linear_project_id: nil)
    else
      find_by(install_token:, linear_team_id:, linear_project_id: nil)
    end
  end
end
