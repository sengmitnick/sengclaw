class Webhooks::LinearController < ActionController::API
  # Must respond within 5 seconds — immediately enqueue and return 200
  def receive
    raw_body = request.raw_post

    unless valid_signature?(raw_body)
      Rails.logger.warn "Linear webhook: invalid signature from #{request.remote_ip}"
      return head :unauthorized
    end

    payload = JSON.parse(raw_body)
    event_type = request.headers["Linear-Event"]

    # Enqueue async processing — do NOT block here
    LinearWebhookJob.perform_later(payload: payload, event_type: event_type)

    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private

  def valid_signature?(body)
    secret = ENV.fetch("LINEAR_WEBHOOK_SECRET", nil)
    return true if secret.blank?  # skip verification in dev if not configured

    expected = OpenSSL::HMAC.hexdigest("SHA256", secret, body)
    received = request.headers["Linear-Signature"]

    # Timing-safe comparison
    ActiveSupport::SecurityUtils.secure_compare(expected, received.to_s)
  end
end
