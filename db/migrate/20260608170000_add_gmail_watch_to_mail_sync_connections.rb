class AddGmailWatchToMailSyncConnections < ActiveRecord::Migration[7.2]
  def change
    add_column :mail_sync_connections, :gmail_history_id, :string
    add_column :mail_sync_connections, :gmail_watch_expires_at, :datetime
  end
end
