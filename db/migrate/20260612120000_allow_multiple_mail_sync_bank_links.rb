class AllowMultipleMailSyncBankLinks < ActiveRecord::Migration[7.2]
  def up
    add_column :mail_sync_bank_links, :account_hint, :string

    remove_index :mail_sync_bank_links,
                 name: "index_mail_sync_bank_links_on_connection_and_format"

    add_index :mail_sync_bank_links,
              [ :mail_sync_connection_id, :mail_bank_format_id, :account_id ],
              unique: true,
              name: "index_mail_sync_bank_links_on_connection_format_account"
  end

  def down
    remove_index :mail_sync_bank_links,
                 name: "index_mail_sync_bank_links_on_connection_format_account"

    add_index :mail_sync_bank_links,
              [ :mail_sync_connection_id, :mail_bank_format_id ],
              unique: true,
              name: "index_mail_sync_bank_links_on_connection_and_format"

    remove_column :mail_sync_bank_links, :account_hint
  end
end
