class AddSyncFromAtToMailSyncConnections < ActiveRecord::Migration[7.2]
  def up
    add_column :mail_sync_connections, :sync_from_at, :datetime

    # Stop backfilling old unread bank emails for existing connections.
    execute <<~SQL.squish
      UPDATE mail_sync_connections SET sync_from_at = NOW() WHERE sync_from_at IS NULL
    SQL

    change_column_null :mail_sync_connections, :sync_from_at, false
  end

  def down
    remove_column :mail_sync_connections, :sync_from_at
  end
end
