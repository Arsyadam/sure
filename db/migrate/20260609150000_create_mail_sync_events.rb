class CreateMailSyncEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :mail_sync_events, id: :uuid do |t|
      t.references :mail_sync_connection, foreign_key: true, type: :uuid, null: true
      t.string :level, null: false, default: "info"
      t.string :event, null: false
      t.text :message
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :mail_sync_events, :created_at
    add_index :mail_sync_events, [ :mail_sync_connection_id, :created_at ]
  end
end
