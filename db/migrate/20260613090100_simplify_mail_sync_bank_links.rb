class SimplifyMailSyncBankLinks < ActiveRecord::Migration[7.2]
  def up
    migrate_hints_to_accounts
    deduplicate_bank_links

    remove_index :mail_sync_bank_links,
                 name: "index_mail_sync_bank_links_on_connection_format_account",
                 if_exists: true

    remove_foreign_key :mail_sync_bank_links, :accounts, if_exists: true
    remove_column :mail_sync_bank_links, :account_id
    remove_column :mail_sync_bank_links, :account_hint

    add_index :mail_sync_bank_links,
              [ :mail_sync_connection_id, :mail_bank_format_id ],
              unique: true,
              name: "index_mail_sync_bank_links_on_connection_and_format"
  end

  def down
    remove_index :mail_sync_bank_links,
                 name: "index_mail_sync_bank_links_on_connection_and_format",
                 if_exists: true

    add_reference :mail_sync_bank_links, :account, null: true, foreign_key: true, type: :uuid
    add_column :mail_sync_bank_links, :account_hint, :string

    add_index :mail_sync_bank_links,
              [ :mail_sync_connection_id, :mail_bank_format_id, :account_id ],
              unique: true,
              name: "index_mail_sync_bank_links_on_connection_format_account"
  end

  private

    def migrate_hints_to_accounts
      return unless column_exists?(:mail_sync_bank_links, :account_hint)

      execute <<~SQL.squish
        UPDATE accounts
        SET account_number_last4 = mail_sync_bank_links.account_hint
        FROM mail_sync_bank_links
        WHERE mail_sync_bank_links.account_id = accounts.id
          AND mail_sync_bank_links.account_hint IS NOT NULL
          AND mail_sync_bank_links.account_hint <> ''
          AND (accounts.account_number_last4 IS NULL OR accounts.account_number_last4 = '')
      SQL
    end

    def deduplicate_bank_links
      return unless column_exists?(:mail_sync_bank_links, :account_id)

      execute <<~SQL.squish
        DELETE FROM mail_sync_bank_links
        WHERE id IN (
          SELECT id FROM (
            SELECT id,
                   ROW_NUMBER() OVER (
                     PARTITION BY mail_sync_connection_id, mail_bank_format_id
                     ORDER BY created_at ASC
                   ) AS row_num
            FROM mail_sync_bank_links
          ) ranked
          WHERE row_num > 1
        )
      SQL
    end
end
