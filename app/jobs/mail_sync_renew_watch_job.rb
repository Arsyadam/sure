class MailSyncRenewWatchJob < ApplicationJob
  queue_as :scheduled
  sidekiq_options lock: :until_executed, on_conflict: :log

  def perform
    return unless MailSync::Configuration.push_configured?

    MailSyncConnection.active.find_each do |connection|
      MailSync::WatchService.new(connection).renew_if_needed!
    rescue => e
      Rails.logger.error("[MailSyncRenewWatchJob] #{connection.id}: #{e.message}")
    end
  end
end
