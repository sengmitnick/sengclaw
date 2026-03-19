require "net/http"

class Oauth::LinearController < ApplicationController
  # OAuth flow does not need CSRF protection (callback comes from Linear)
  skip_before_action :verify_authenticity_token, only: [:callback]

  # GET /oauth/linear/authorize?install_token=UUID
  # Redirects user to Linear OAuth authorization page
  def authorize
    install_token = params[:install_token]
    return render plain: "install_token is required", status: :bad_request if install_token.blank?

    # Pass install_token via OAuth state param (more reliable than session across domains)
    redirect_to linear_authorize_url(install_token), allow_other_host: true
  end

  # GET /oauth/linear/callback?code=XXX&state=XXX
  # Linear redirects here after user authorizes
  def callback
    # Read install_token from state param (passed through OAuth flow, no session needed)
    install_token = params[:state]
    return render plain: "install_token missing from state param", status: :bad_request if install_token.blank?

    code = params[:code]
    return render plain: "Authorization code missing", status: :bad_request if code.blank?

    token_data = exchange_code_for_token(code)
    return render plain: "Failed to exchange token", status: :bad_gateway unless token_data

    actor_id = fetch_actor_id(token_data[:access_token])

    installation = LinearInstallation.find_or_initialize_by(install_token: install_token)
    installation.update!(
      workspace_id: token_data[:organization_id],
      access_token: token_data[:access_token],
      refresh_token: token_data[:refresh_token],
      expires_at: token_data[:expires_at],
      linear_actor_id: actor_id
    )

    render plain: "✅ SengClaw connected to Linear! You can close this window.", status: :ok
  end

  private

  def linear_authorize_url(install_token)
    params = {
      client_id: ENV.fetch("LINEAR_CLIENT_ID"),
      redirect_uri: linear_callback_url,
      response_type: "code",
      scope: "read,write,app:assignable,app:mentionable",
      actor: "app",
      state: install_token  # pass through for verification (optional extra check)
    }
    "https://linear.app/oauth/authorize?#{params.to_query}"
  end

  def linear_callback_url
    "#{ENV.fetch('PUBLIC_HOST', 'http://localhost:3002')}/oauth/linear/callback"
  end

  def exchange_code_for_token(code)
    uri = URI("https://api.linear.app/oauth/token")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/x-www-form-urlencoded"
    req.body = URI.encode_www_form(
      code: code,
      redirect_uri: linear_callback_url,
      client_id: ENV.fetch("LINEAR_CLIENT_ID"),
      client_secret: ENV.fetch("LINEAR_CLIENT_SECRET"),
      grant_type: "authorization_code"
    )

    response = http.request(req)
    return nil unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    Rails.logger.info "Linear token response keys: #{data.keys.inspect}"
    Rails.logger.info "Linear token response: #{data.except('access_token', 'refresh_token').inspect}"

    # Linear app actor tokens don't include organizationId in token response.
    # Fetch organization info via GraphQL after getting the token.
    access_token = data["access_token"]
    workspace_id = fetch_organization_id(access_token)
    Rails.logger.info "Linear organization_id fetched: #{workspace_id.inspect}"

    {
      access_token: access_token,
      refresh_token: data["refresh_token"],
      expires_at: data["expires_in"] ? Time.current + data["expires_in"].to_i.seconds : nil,
      organization_id: workspace_id
    }
  rescue => e
    Rails.logger.error "Linear token exchange failed: #{e.message}"
    nil
  end

  def fetch_organization_id(access_token)
    uri = URI("https://api.linear.app/graphql")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = access_token
    req["Content-Type"] = "application/json"
    req.body = { query: "{ organization { id } }" }.to_json

    response = http.request(req)
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).dig("data", "organization", "id")
  rescue => e
    Rails.logger.error "Linear organization ID fetch failed: #{e.message}"
    nil
  end

  def fetch_actor_id(access_token)
    uri = URI("https://api.linear.app/graphql")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = access_token
    req["Content-Type"] = "application/json"
    req.body = { query: "{ viewer { id } }" }.to_json

    response = http.request(req)
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).dig("data", "viewer", "id")
  rescue => e
    Rails.logger.error "Linear actor ID fetch failed: #{e.message}"
    nil
  end
end
