class AgentTask < ApplicationRecord
  STATUSES = %w[pending dispatched running done failed timeout].freeze

  validates :agent_session_id, presence: true, uniqueness: true
  validates :issue_id, presence: true
  validates :workspace_id, presence: true
  validates :install_token, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: %w[pending dispatched running]) }

  def mark_dispatched! = update!(status: "dispatched")
  def mark_running!    = update!(status: "running")
  def mark_done!       = update!(status: "done")
  def mark_failed!(msg) = update!(status: "failed", error_message: msg)
  def mark_timeout!    = update!(status: "timeout")
end
