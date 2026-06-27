class CreateMailSyncTables < ActiveRecord::Migration[7.2]
  def change
    create_table :mail_bank_formats, id: :uuid do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.text :description
      t.string :parser, null: false
      t.boolean :enabled, null: false, default: true
      t.integer :sort_order, null: false, default: 0

      t.timestamps
    end

    add_index :mail_bank_formats, :code, unique: true

    create_table :mail_sync_connections, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string :gmail_email, null: false
      t.text :refresh_token, null: false
      t.string :gmail_label_id
      t.jsonb :bank_codes, null: false, default: []
      t.boolean :enabled, null: false, default: true
      t.datetime :last_synced_at

      t.timestamps
    end

    add_index :mail_sync_connections, [ :family_id, :user_id ], unique: true
    add_index :mail_sync_connections, :enabled

    create_table :mail_sync_processed_messages, id: :uuid do |t|
      t.references :mail_sync_connection, null: false, foreign_key: true, type: :uuid
      t.string :gmail_message_id, null: false

      t.timestamps
    end

    add_index :mail_sync_processed_messages,
              [ :mail_sync_connection_id, :gmail_message_id ],
              unique: true,
              name: "index_mail_sync_processed_on_connection_and_message"

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          INSERT INTO mail_bank_formats (id, code, name, description, parser, enabled, sort_order, created_at, updated_at)
          VALUES
            (gen_random_uuid(), 'BCA', 'BCA (myBCA)', 'Email notifikasi myBCA / bca.co.id', 'bca', true, 1, NOW(), NOW()),
            (gen_random_uuid(), 'CIMB', 'CIMB Niaga / OCTO', 'Email notifikasi CIMB Niaga & OCTO', 'cimb', true, 2, NOW(), NOW())
        SQL
      end
    end
  end
end
