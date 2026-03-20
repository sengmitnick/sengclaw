require "net/http"
require "uri"
require "json"

class LinearActivityService < ApplicationService
  GRAPHQL_ENDPOINT = "https://api.linear.app/graphql"

  # Activity content types supported by Linear Agent API
  ACTIVITY_TYPES = %w[thought action elicitation response error].freeze

  # Create an agent activity on a Linear AgentSession.
  #
  # access_token      - the workspace's Linear OAuth token
  # agent_session_id  - the AgentSession ID from the webhook payload
  # type              - one of "thought", "action", "response", "elicitation", "error"
  # body              - markdown text content
  # action_name       - (for type="action") the action label, e.g. "Searching"
  # parameter         - (for type="action") the parameter string
  # result            - (for type="action") optional result string after completion
  #
  # Returns the created activity, or raises on failure.
  def initialize(access_token:, agent_session_id:, type:, body: nil,
                 action_name: nil, parameter: nil, result: nil)
    @access_token     = access_token
    @agent_session_id = agent_session_id
    @type             = type
    @body             = body
    @action_name      = action_name
    @parameter        = parameter
    @result           = result
  end

  def call
    raise ArgumentError, "Invalid activity type: #{@type}" unless ACTIVITY_TYPES.include?(@type)

    content = build_content

    mutation = <<~GRAPHQL
      mutation AgentActivityCreate($input: AgentActivityCreateInput!) {
        agentActivityCreate(input: $input) {
          success
          agentActivity {
            id
            createdAt
          }
        }
      }
    GRAPHQL

    uri = URI(GRAPHQL_ENDPOINT)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"]  = "application/json"
    req["Authorization"] = @access_token
    req.body = {
      query: mutation,
      variables: {
        input: {
          agentSessionId: @agent_session_id,
          content: content
        }
      }
    }.to_json

    response = http.request(req)
    result_data = JSON.parse(response.body)

    if result_data["errors"].present?
      raise "Linear API error: #{result_data['errors'].map { |e| e['message'] }.join(', ')}"
    end

    unless result_data.dig("data", "agentActivityCreate", "success")
      raise "LinearActivityService: agentActivityCreate returned success=false. Response: #{response.body}"
    end

    activity = result_data.dig("data", "agentActivityCreate", "agentActivity")
    Rails.logger.info "LinearActivityService: created #{@type} activity #{activity&.dig('id')} for session #{@agent_session_id}"
    activity
  end

  private

  def build_content
    case @type
    when "thought", "elicitation", "response", "error"
      { type: @type, body: @body }
    when "action"
      content = { type: "action", action: @action_name, parameter: @parameter }
      content[:result] = @result if @result.present?
      content
    end
  end
end
