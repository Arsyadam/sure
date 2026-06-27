class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_authentication

  def plaid
    webhook_body = request.body.read
    plaid_verification_header = request.headers["Plaid-Verification"]

    client = Provider::Registry.plaid_provider_for_region(:us)

    client.validate_webhook!(plaid_verification_header, webhook_body)

    PlaidItem::WebhookProcessor.new(webhook_body).process

    render json: { received: true }, status: :ok
  rescue => error
    Sentry.capture_exception(error)
    render json: { error: "Invalid webhook: #{error.message}" }, status: :bad_request
  end

  def plaid_eu
    webhook_body = request.body.read
    plaid_verification_header = request.headers["Plaid-Verification"]

    client = Provider::Registry.plaid_provider_for_region(:eu)

    client.validate_webhook!(plaid_verification_header, webhook_body)

    PlaidItem::WebhookProcessor.new(webhook_body).process

    render json: { received: true }, status: :ok
  rescue => error
    Sentry.capture_exception(error)
    render json: { error: "Invalid webhook: #{error.message}" }, status: :bad_request
  end

  def stripe
    stripe_provider = Provider::Registry.get_provider(:stripe)

    begin
      webhook_body = request.body.read
      sig_header = request.env["HTTP_STRIPE_SIGNATURE"]

      stripe_provider.process_webhook_later(webhook_body, sig_header)

      head :ok
    rescue JSON::ParserError => error
      Sentry.capture_exception(error)
      Rails.logger.error "JSON parser error: #{error.message}"
      head :bad_request
    rescue Stripe::SignatureVerificationError => error
      Sentry.capture_exception(error)
      Rails.logger.error "Stripe signature verification error: #{error.message}"
      head :bad_request
    end
  end

  def gmail_mail_sync
    webhook_body = request.body.read
    token = request.headers["Authorization"]&.sub(/\ABearer /i, "")
    audience = MailSync::Configuration.gmail_webhook_url || webhooks_gmail_mail_sync_url

    Rails.logger.debug("[MailSync] webhook.incoming audience=#{audience} token_present=#{token.present?}")

    MailSync::PubsubVerifier.verify!(token, audience: audience)

    envelope = JSON.parse(webhook_body)
    raw = envelope.dig("message", "data").to_s
    payload = JSON.parse(Base64.decode64(raw))
    email = payload["emailAddress"].to_s.downcase
    history_id = payload["historyId"].to_s

    connection = MailSyncConnection.active.find_by(gmail_email: email)
    unless connection
      MailSync::EventLogger.log(
        "webhook.ignored",
        "No active connection for #{email}",
        level: "warn",
        email: email,
        history_id: history_id
      )
      render json: { received: true }, status: :ok
      return
    end

    if connection.gmail_history_id.present? && history_id.to_i <= connection.gmail_history_id.to_i
      MailSync::EventLogger.log(
        "webhook.noop",
        "History #{history_id} already covered (stored #{connection.gmail_history_id})",
        connection: connection,
        history_id: history_id
      )
      render json: { received: true }, status: :ok
      return
    end

    MailSync::EventLogger.log(
      "webhook.received",
      "Push notification for #{email}",
      connection: connection,
      history_id: history_id,
      pubsub_message_id: envelope.dig("message", "messageId")
    )

    MailSyncGmailPushJob.perform_later(connection.id, history_id)
    render json: { received: true }, status: :ok
  rescue => error
    MailSync::EventLogger.log("webhook.failed", error.message, level: "error")
    Sentry.capture_exception(error) if defined?(Sentry)
    render json: { error: error.message }, status: :bad_request
  end
end
