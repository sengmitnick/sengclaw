class Api::V1::ProjectMappingsController < Api::BaseController
  before_action :authenticate_install_token!

  # GET /api/v1/project_mappings
  # List all mappings for this OpenClacky instance
  def index
    mappings = ProjectMapping.where(install_token: current_install_token)
    render json: mappings.map { |m| serialize(m) }
  end

  # POST /api/v1/project_mappings
  # Create or update a mapping
  # Body: { linear_team_id:, local_path:, linear_project_id: (optional), name: (optional) }
  def create
    mapping = ProjectMapping.find_or_initialize_by(
      install_token: current_install_token,
      linear_team_id: params.require(:linear_team_id)
    )
    mapping.assign_attributes(
      local_path: params.require(:local_path),
      linear_project_id: params[:linear_project_id],
      name: params[:name]
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
      id: mapping.id,
      install_token: mapping.install_token,
      linear_team_id: mapping.linear_team_id,
      linear_project_id: mapping.linear_project_id,
      local_path: mapping.local_path,
      name: mapping.name,
      created_at: mapping.created_at
    }
  end
end
