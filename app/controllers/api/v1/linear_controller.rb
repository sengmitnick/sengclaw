# frozen_string_literal: true

# Api::V1::LinearController — Linear data proxy for workspace skill.
#
# All endpoints require X-Install-Token header.
# The token is used to look up the LinearInstallation and its access_token.
#
# Endpoints:
#   GET  /api/v1/linear/teams_and_projects  — list teams + projects
#   POST /api/v1/linear/projects            — create a new project in Linear
class Api::V1::LinearController < Api::BaseController
  before_action :authenticate_install_token!

  # GET /api/v1/linear/teams_and_projects
  #
  # Returns:
  #   { teams: [{ id, name, key, projects: [{ id, name, state }] }] }
  def teams_and_projects
    service = LinearApiService.new(access_token: @installation.access_token)
    teams   = service.teams_and_projects
    render json: { teams: teams }
  rescue => e
    Rails.logger.error "LinearController#teams_and_projects error: #{e.message}"
    render json: { error: "Failed to fetch Linear data: #{e.message}" }, status: :bad_gateway
  end

  # POST /api/v1/linear/projects
  #
  # Body: { team_id: "...", name: "..." }
  #
  # Returns:
  #   { project: { id, name, state } }
  def create_project
    team_id = params.require(:team_id)
    name    = params.require(:name).to_s.strip

    return render json: { error: "name is required" }, status: :bad_request if name.empty?

    service = LinearApiService.new(access_token: @installation.access_token)
    project = service.create_project(team_id: team_id, name: name)
    render json: { project: project }, status: :created
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :bad_request
  rescue => e
    Rails.logger.error "LinearController#create_project error: #{e.message}"
    render json: { error: "Failed to create Linear project: #{e.message}" }, status: :bad_gateway
  end

  private

  def authenticate_install_token!
    token = request.headers["X-Install-Token"] || params[:install_token]
    @installation = LinearInstallation.find_by(install_token: token)
    render json: { error: "Unauthorized" }, status: :unauthorized unless @installation
  end
end
