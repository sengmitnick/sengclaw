module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :install_token

    def connect
      token = request.params[:install_token]
      reject_unauthorized_connection if token.blank?

      installation = LinearInstallation.find_by(install_token: token)
      reject_unauthorized_connection unless installation

      # Strict auth: ensure Linear token is still valid (not expired/revoked)
      reject_unauthorized_connection if installation.access_token.blank?

      self.install_token = token
      Rails.logger.info "ActionCable: connected install_token=#{token}"
    end

    def disconnect
      Rails.logger.info "ActionCable: disconnected install_token=#{install_token}"
    end
  end
end
