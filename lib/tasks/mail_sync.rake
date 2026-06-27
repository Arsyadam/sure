namespace :mail_sync do
  desc "Remove bulk-imported mail sync transactions and reset processed message log"
  task cleanup_imports: :environment do
    total = 0
    MailSyncConnection.find_each do |connection|
      deleted = MailSync::CleanupImportedEntries.new(connection).cleanup!
      total += deleted
      puts "Connection #{connection.gmail_email}: removed #{deleted} entries"
    end
    puts "Done. Removed #{total} entries total."
  end

  desc "Trace a Gmail message_id (MESSAGE_ID=... or first arg)"
  task trace_message: :environment do
    message_id = ENV["MESSAGE_ID"].presence || ARGV[0]
    raise "Usage: MESSAGE_ID=abc bin/rails mail_sync:trace_message" if message_id.blank?

    connection = MailSyncConnection.active.first
    raise "No active mail sync connection" unless connection

    puts MailSync::MessageTracer.new(connection).trace(message_id)
  end

  desc "List messagesAdded from Gmail history (FROM_HISTORY_ID=... or first arg)"
  task trace_history: :environment do
    start_id = ENV["FROM_HISTORY_ID"].presence || ARGV[0]
    raise "Usage: FROM_HISTORY_ID=1116674 bin/rails mail_sync:trace_history" if start_id.blank?

    connection = MailSyncConnection.active.first
    raise "No active mail sync connection" unless connection

    puts MailSync::MessageTracer.new(connection).trace_history(start_id)
  end

  desc "Start or renew Gmail push watch for all active connections"
  task start_watches: :environment do
    raise "MAIL_SYNC_GMAIL_PUBSUB_TOPIC is not set" unless MailSync::Configuration.push_configured?

    MailSyncConnection.active.find_each do |connection|
      MailSync::WatchService.new(connection).start!
      puts "Watch started for #{connection.gmail_email}"
    rescue => e
      puts "Failed for #{connection.gmail_email}: #{e.message}"
    end
  end
end
