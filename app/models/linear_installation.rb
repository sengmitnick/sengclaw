class LinearInstallation < ApplicationRecord
  validates :install_token, presence: true, uniqueness: true
  validates :workspace_id, presence: true
  validates :access_token, presence: true

  # Find by install_token, raise if not found
  def self.find_by_token!(token)
    find_by!(install_token: token)
  end

  def token_expired?
    expires_at.present? && expires_at < Time.current
  end

  def token_expiring_soon?
    expires_at.present? && expires_at < 5.minutes.from_now
  end
end
