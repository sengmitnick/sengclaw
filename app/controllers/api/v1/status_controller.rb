# frozen_string_literal: true

class Api::V1::StatusController < Api::BaseController
  before_action :require_install_token!

  # GET /api/v1/status
  # Returns the connection status for the current install_token.
  #
  # Response:
  #   { linear_connected: true/false }
  #
  # linear_connected is true when a LinearInstallation record exists for this token,
  # meaning the user has completed the OAuth flow at least once.
  #
  # Note: unlike other endpoints, this does NOT require a LinearInstallation to exist.
  # It is intentionally callable before OAuth is complete, to poll readiness.
  def show
    connected = LinearInstallation.exists?(install_token: @install_token)
    render json: { linear_connected: connected }
  end

  private

  def require_install_token!
    @install_token = request.headers["X-Install-Token"].to_s.strip
    render json: { error: "X-Install-Token header is required" }, status: :unauthorized if @install_token.empty?
  end
end
