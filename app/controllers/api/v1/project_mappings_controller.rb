class Api::V1::ProjectMappingsController < Api::BaseController
  before_action :authenticate_install_token!

  # GET /api/v1/project_mappings
  # List all mappings for this OpenClacky instance
  def index
    mappings = ProjectMapping.where(install_token: current_install_token)
    render json: mappings.map { |m| serialize(m) }
  end

  # POST /api/v1/project_mappings
  # Create or update a mapping (upsert by project_id or team_id).
  #
  # Project-level (specific): pass linear_project_id + linear_team_id + local_path
  # Team-level   (default):   pass linear_team_id + local_path, omit linear_project_id
  #
  # Body params:
  #   linear_team_id    (required)
  #   local_path        (required)
  #   linear_project_id (optional — if present, creates a project-level mapping)
  #   name              (optional)
  def create
    team_id    = params.require(:linear_team_id)
    local_path = params.require(:local_path)
    project_id = params[:linear_project_id].presence

    # Scope the upsert key by whether this is a project-level or team-level mapping
    lookup_attrs = if project_id
      # Project-level: match on install_token + linear_project_id
      { install_token: current_install_token, linear_project_id: project_id }
    else
      # Team-level: match on install_token + linear_team_id where project_id is null
      { install_token: current_install_token, linear_team_id: team_id, linear_project_id: nil }
    end

    mapping = ProjectMapping.find_or_initialize_by(lookup_attrs)
    mapping.assign_attributes(
      linear_team_id:    team_id,
      local_path:        local_path,
      linear_project_id: project_id,
      name:              params[:name]
    )

    if mapping.save
      render json: serialize(mapping), status: mapping.previously_new_record? ? :created : :ok
    else
      render json: { errors: mapping.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/project_mappings/:id
  def destroy
    mapping = ProjectMapping.find_by!(id: params[:id], install_token: current_install_token)
    mapping.destroy!
    head :no_content
  end

  private

  def authenticate_install_token!
    token = request.headers["X-Install-Token"] || params[:install_token]
    installation = LinearInstallation.find_by(install_token: token)
    render json: { error: "Unauthorized" }, status: :unauthorized unless installation
    @current_install_token = token
  end

  def current_install_token
    @current_install_token
  end

  def serialize(mapping)
    {
      id:                mapping.id,
      install_token:     mapping.install_token,
      linear_team_id:    mapping.linear_team_id,
      linear_project_id: mapping.linear_project_id,
      local_path:        mapping.local_path,
      name:              mapping.name,
      created_at:        mapping.created_at
    }
  end
end
