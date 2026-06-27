module MailSync
  class WatchService
    def initialize(connection)
      @connection = connection
    end

    def start!
      topic = Configuration.gmail_pubsub_topic
      raise StandardError, "MAIL_SYNC_GMAIL_PUBSUB_TOPIC is not set" if topic.blank?

      gmail = GmailClient.new(refresh_token: @connection.refresh_token)
      response = gmail.start_watch(topic_name: topic)

      expires_at = Time.at(response["expiration"].to_i / 1000.0)
      @connection.update!(
        gmail_history_id: response["historyId"].to_s,
        gmail_watch_expires_at: expires_at
      )

      EventLogger.log(
        "watch.started",
        "Gmail watch active until #{expires_at.iso8601}",
        connection: @connection,
        topic: topic,
        history_id: response["historyId"],
        expires_at: expires_at.iso8601
      )

      response
    rescue => e
      EventLogger.log(
        "watch.failed",
        e.message,
        level: "error",
        connection: @connection,
        topic: topic
      )
      raise
    end

    def stop!
      GmailClient.new(refresh_token: @connection.refresh_token).stop_watch
      @connection.update!(gmail_watch_expires_at: nil)
      EventLogger.log("watch.stopped", "Gmail watch stopped", connection: @connection)
    rescue => e
      EventLogger.log("watch.stop_failed", e.message, level: "warn", connection: @connection)
    end

    def renew_if_needed!
      return unless @connection.enabled?
      return if @connection.gmail_watch_expires_at.present? && @connection.gmail_watch_expires_at > 2.days.from_now

      EventLogger.log("watch.renewing", "Renewing expiring watch", connection: @connection)
      start!
    end
  end
end
