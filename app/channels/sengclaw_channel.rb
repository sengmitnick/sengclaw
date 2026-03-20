class SengclawChannel < ApplicationCable::Channel
  # OpenClacky subscribes to this channel on startup
  def subscribed
    stream_from channel_key(install_token)
    Rails.logger.info "SengclawChannel: subscribed #{install_token}"

    # Flush any pending tasks for this instance
    flush_pending_tasks
  end

  def unsubscribed
    Rails.logger.info "SengclawChannel: unsubscribed #{install_token}"
  end

  # OpenClacky → sengclaw: post a thought/action/response activity back to Linear
  # data: { agent_session_id:, type: "thought"|"action"|"response", body: "..." }
  def post_activity(data)
    task = AgentTask.find_by(agent_session_id: data["agent_session_id"])
    return unless task

    installation = LinearInstallation.find_by(install_token: task.install_token)
    return unless installation&.access_token

    LinearActivityService.new(
      access_token:     installation.access_token,
      agent_session_id: data["agent_session_id"],
      type:             data["type"],
      body:             data["body"]
    ).call
  rescue => e
    Rails.logger.error "SengclawChannel#post_activity failed: #{e.message}"
  end

  # OpenClacky → sengclaw: task completed
  def task_completed(data)
    task = AgentTask.find_by(agent_session_id: data["agent_session_id"])
    return unless task

    task.mark_done!
    Rails.logger.info "SengclawChannel: task completed #{data['agent_session_id']}"

    # Post final response activity to Linear if body provided
    if data["response"].present?
      post_activity(data.merge("type" => "response", "body" => data["response"]))
    end
  end

  # OpenClacky → sengclaw: task failed
  def task_failed(data)
    task = AgentTask.find_by(agent_session_id: data["agent_session_id"])
    return unless task

    task.mark_failed!(data["error"])

    # Notify Linear about the failure
    installation = LinearInstallation.find_by(install_token: task.install_token)
    if installation&.access_token
      LinearActivityService.new(
        access_token:     installation.access_token,
        agent_session_id: data["agent_session_id"],
        type:             "response",
        body:             "❌ Task failed: #{data['error']}"
      ).call rescue nil
    end
  end

  # OpenClacky → sengclaw: task started running
  def task_running(data)
    task = AgentTask.find_by(agent_session_id: data["agent_session_id"])
    task&.mark_running!
  end

  # Class method: dispatch a new task to a connected OpenClacky instance
  # Returns true if the instance is connected, false otherwise
  def self.dispatch_task(install_token:, task:, payload:, local_path: nil)
    channel = channel_key_for(install_token)
    # AgentSessionEvent: agentSession and promptContext are at top level
    ActionCable.server.broadcast(channel, {
      type: "new_task",
      agent_session_id: task.agent_session_id,
      issue_id: task.issue_id,
      workspace_id: task.workspace_id,
      local_path: local_path,
      prompt_context: payload["promptContext"] || payload.dig("data", "promptContext"),
      agent_session: payload["agentSession"] || payload.dig("data", "agentSession")
    })
    true
  rescue => e
    Rails.logger.error "SengclawChannel.dispatch_task failed: #{e.message}"
    false
  end

  def self.notify_session_updated(install_token:, agent_session_id:, payload:)
    channel = channel_key_for(install_token)
    ActionCable.server.broadcast(channel, {
      type: "session_updated",
      agent_session_id: agent_session_id,
      prompt_context: payload["promptContext"] || payload.dig("data", "promptContext"),
      agent_session: payload["agentSession"] || payload.dig("data", "agentSession")
    })
  end

  private

  def channel_key(token)
    self.class.channel_key_for(token)
  end

  def self.channel_key_for(token)
    "sengclaw:#{token}"
  end

  # When OpenClacky reconnects, dispatch any tasks that were pending while offline
  def flush_pending_tasks
    pending = AgentTask.where(install_token: install_token, status: "pending")
    pending.each do |task|
      payload = task.webhook_payload ? JSON.parse(task.webhook_payload) : {}
      dispatched = SengclawChannel.dispatch_task(install_token: install_token, task: task, payload: payload)
      task.mark_dispatched! if dispatched
    end
    Rails.logger.info "SengclawChannel: flushed #{pending.count} pending tasks for #{install_token}" if pending.any?
  end
end
