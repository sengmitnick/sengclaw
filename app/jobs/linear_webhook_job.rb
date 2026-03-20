class LinearWebhookJob < ApplicationJob
  queue_as :default

  def perform(payload:, event_type:)
    case event_type
    when "AgentSessionEvent"
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
    # AgentSessionEvent: agentSession and organizationId are at top level (not nested under "data")
    agent_session = payload["agentSession"] || payload.dig("data", "agentSession")
    return unless agent_session

    session_id = agent_session["id"]
    workspace_id = payload["organizationId"] || payload.dig("data", "organizationId")

    case action
    when "created"
      dispatch_new_task(session_id, workspace_id, payload, agent_session)
    when "updated", "prompted"
      # User added more context — notify OpenClacky
      notify_session_updated(session_id, payload)
    end
  end

  def dispatch_new_task(session_id, workspace_id, payload, agent_session)
    # Find which LinearInstallation owns this workspace
    installation = LinearInstallation.find_by(workspace_id: workspace_id)
    unless installation
      Rails.logger.warn "LinearWebhookJob: no installation found for workspace #{workspace_id}"
      return
    end

    issue_id   = agent_session.dig("issue", "id")
    team_id    = agent_session.dig("issue", "team", "id")
    project_id = agent_session.dig("issue", "project", "id")

    # Resolve which local project path this task maps to
    mapping = ProjectMapping.resolve(
      install_token:     installation.install_token,
      linear_team_id:    team_id,
      linear_project_id: project_id
    )

    if mapping.nil?
      Rails.logger.warn "LinearWebhookJob: no ProjectMapping for team=#{team_id} project=#{project_id} — task will proceed without local_path"
    end

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
      payload: payload,
      local_path: mapping&.local_path
    )

    if dispatched
      task.mark_dispatched!
      # Acknowledge receipt to Linear — must respond within 10s to avoid "Did not respond"
      ack_to_linear(installation.access_token, session_id, "✅ 任务已收到，SengClaw Dev 正在处理中...")
    else
      Rails.logger.warn "LinearWebhookJob: no active connection for install_token #{installation.install_token}"
      # OpenClacky is offline — inform Linear and keep task pending for retry
      ack_to_linear(installation.access_token, session_id,
        "⚠️ SengClaw Dev 当前不在线。请在本地启动 OpenClacky，任务将自动恢复执行。")
    end
  end

  # Send an immediate acknowledgement activity to Linear to avoid "Did not respond" timeout.
  def ack_to_linear(access_token, session_id, message)
    LinearActivityService.new(
      access_token:     access_token,
      agent_session_id: session_id,
      type:             "thought",
      body:             message
    ).call
  rescue => e
    Rails.logger.error "LinearWebhookJob: failed to ack Linear for session #{session_id}: #{e.message}"
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
