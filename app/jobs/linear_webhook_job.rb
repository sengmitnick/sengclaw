class LinearWebhookJob < ApplicationJob
  queue_as :default

  def perform(payload:, event_type:)
    case event_type
    when "AgentSession"
      handle_agent_session(payload)
    when "OAuthApp"
      handle_oauth_app_event(payload)
    else
      Rails.logger.info "LinearWebhookJob: unhandled event type #{event_type}"
    end
  end

  private

  def handle_agent_session(payload)
    action = payload["action"]
    agent_session = payload.dig("data", "agentSession")
    return unless agent_session

    session_id = agent_session["id"]
    workspace_id = payload["organizationId"] || payload.dig("data", "organizationId")

    case action
    when "created"
      dispatch_new_task(session_id, workspace_id, payload)
    when "updated"
      # User added more context — notify OpenClacky
      notify_session_updated(session_id, payload)
    end
  end

  def dispatch_new_task(session_id, workspace_id, payload)
    # Find which LinearInstallation owns this workspace
    installation = LinearInstallation.find_by(workspace_id: workspace_id)
    unless installation
      Rails.logger.warn "LinearWebhookJob: no installation found for workspace #{workspace_id}"
      return
    end

    issue_id = payload.dig("data", "agentSession", "issue", "id")

    # Idempotent: skip if already exists
    task = AgentTask.find_or_create_by!(agent_session_id: session_id) do |t|
      t.install_token = installation.install_token
      t.issue_id = issue_id.to_s
      t.workspace_id = workspace_id.to_s
      t.status = "pending"
      t.webhook_payload = payload.to_json
    end

    return if task.status != "pending"

    # Route to the connected OpenClacky instance via ActionCable
    dispatched = SengclawChannel.dispatch_task(
      install_token: installation.install_token,
      task: task,
      payload: payload
    )

    if dispatched
      task.mark_dispatched!
    else
      Rails.logger.warn "LinearWebhookJob: no active connection for install_token #{installation.install_token}"
      # OpenClacky is offline — task stays pending, will retry when it reconnects
    end
  end

  def notify_session_updated(session_id, payload)
    task = AgentTask.find_by(agent_session_id: session_id)
    return unless task

    SengclawChannel.notify_session_updated(
      install_token: task.install_token,
      agent_session_id: session_id,
      payload: payload
    )
  end

  def handle_oauth_app_event(payload)
    return unless payload["action"] == "revoked"

    # Workspace revoked our app — clean up tokens but keep task history
    organization_id = payload.dig("data", "organizationId")
    LinearInstallation.where(workspace_id: organization_id).update_all(
      access_token: nil,
      refresh_token: nil,
      expires_at: nil
    )
    Rails.logger.info "LinearWebhookJob: cleaned up tokens for revoked workspace #{organization_id}"
  end
end
