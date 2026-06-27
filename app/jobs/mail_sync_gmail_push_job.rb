class MailSyncGmailPushJob < ApplicationJob
  queue_as :default
  # One push job per Gmail connection — avoids duplicate history scans when Pub/Sub bursts.
  sidekiq_options lock: :until_executed,
                  lock_args_method: ->(args) { [ args.first ] },
                  on_conflict: :reject

  def perform(connection_id, history_id)
    connection = MailSyncConnection.active.find_by(id: connection_id)
    unless connection
      MailSync::EventLogger.log("push.skipped", "Connection #{connection_id} not found", level: "warn")
      return
    end

    connection.reload
    if connection.gmail_history_id.present? && history_id.to_i <= connection.gmail_history_id.to_i
      return
    end

    MailSync::EventLogger.log(
      "push.processing",
      "Processing history #{history_id}",
      connection: connection,
      history_id: history_id
    )

    MailSync::Processor.new(connection).process_from_push!(history_id: history_id)
  rescue => e
    MailSync::EventLogger.log(
      "push.failed",
      e.message,
      level: "error",
      connection: connection,
      history_id: history_id
    )
    raise
  end
end
