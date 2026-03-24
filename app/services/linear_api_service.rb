# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

# LinearApiService — general-purpose Linear GraphQL queries and mutations.
#
# Used by the workspace skill to let users browse their Linear teams/projects
# and create new projects during the project binding flow.
class LinearApiService < ApplicationService
  GRAPHQL_ENDPOINT = "https://api.linear.app/graphql"

  def initialize(access_token:)
    @access_token = access_token
  end

  # Fetch all teams and their projects for the authenticated workspace.
  #
  # Returns:
  #   [
  #     { id:, name:, key:, projects: [{ id:, name:, state: }] },
  #     ...
  #   ]
  def teams_and_projects
    query = <<~GRAPHQL
      query TeamsAndProjects {
        teams {
          nodes {
            id
            name
            key
            projects {
              nodes {
                id
                name
                state
              }
            }
          }
        }
      }
    GRAPHQL

    data = graphql!(query)
    teams = data.dig("teams", "nodes") || []

    teams.map do |team|
      {
        id:       team["id"],
        name:     team["name"],
        key:      team["key"],
        projects: (team.dig("projects", "nodes") || []).map do |proj|
          { id: proj["id"], name: proj["name"], state: proj["state"] }
        end
      }
    end
  end

  # Create a new project in Linear under the given team.
  #
  # Params:
  #   team_id  - Linear team ID (required)
  #   name     - project name (required)
  #
  # Returns: { id:, name:, state: }
  def create_project(team_id:, name:)
    mutation = <<~GRAPHQL
      mutation ProjectCreate($input: ProjectCreateInput!) {
        projectCreate(input: $input) {
          success
          project {
            id
            name
            state
          }
        }
      }
    GRAPHQL

    variables = { input: { teamIds: [team_id], name: name } }
    data = graphql!(mutation, variables)

    unless data.dig("projectCreate", "success")
      raise "Linear projectCreate returned success=false"
    end

    proj = data.dig("projectCreate", "project")
    { id: proj["id"], name: proj["name"], state: proj["state"] }
  end

  private

  def graphql!(query, variables = {})
    uri  = URI(GRAPHQL_ENDPOINT)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"]  = "application/json"
    req["Authorization"] = @access_token
    req.body = { query: query, variables: variables }.to_json

    response = http.request(req)
    parsed   = JSON.parse(response.body)

    if parsed["errors"].present?
      messages = parsed["errors"].map { |e| e["message"] }.join(", ")
      raise "Linear API error: #{messages}"
    end

    parsed["data"] || {}
  end
end
