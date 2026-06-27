class AddMailSyncBankLinks < ActiveRecord::Migration[7.2]
  NEW_BANKS = [
    {
      code: "MANDIRI",
      name: "Livin' by Mandiri",
      sender: "noreply.livin@bankmandiri.co.id",
      parser: "mandiri",
      card_type: "debit",
      sort_order: 5,
      description: "Notifikasi QRIS & pembayaran dari Livin' by Mandiri"
    },
    {
      code: "JENIUS_CC",
      name: "Jenius d-Card",
      sender: "jenius_noreply@smbci.com",
      parser: "jenius_credit",
      card_type: "credit",
      sort_order: 6,
      description: "Notifikasi transaksi kartu kredit d-Card Jenius"
    },
    {
      code: "MEGA_CC",
      name: "Bank Mega Kartu Kredit",
      sender: "notifikasi.kartukredit@bankmega.com",
      parser: "mega_credit",
      card_type: "credit",
      sort_order: 7,
      description: "Notifikasi transaksi kartu kredit Bank Mega"
    }
  ].freeze

  LEGACY_CARD_TYPES = {
    "BCA" => "debit",
    "CIMB" => "debit",
    "JAGO" => "debit",
    "GOPAY" => "ewallet"
  }.freeze

  def up
    add_column :mail_bank_formats, :card_type, :string, null: false, default: "debit"

    LEGACY_CARD_TYPES.each do |code, card_type|
      execute <<~SQL.squish
        UPDATE mail_bank_formats SET card_type = '#{card_type}' WHERE code = '#{code}'
      SQL
    end

    create_table :mail_sync_bank_links, id: :uuid do |t|
      t.references :mail_sync_connection, null: false, foreign_key: true, type: :uuid
      t.references :mail_bank_format, null: false, foreign_key: true, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :mail_sync_bank_links,
              [ :mail_sync_connection_id, :mail_bank_format_id ],
              unique: true,
              name: "index_mail_sync_bank_links_on_connection_and_format"

    NEW_BANKS.each do |bank|
      next if MailBankFormat.exists?(code: bank[:code])

      MailBankFormat.create!(
        code: bank[:code],
        name: bank[:name],
        sender_email: bank[:sender],
        description: bank[:description],
        parser: bank[:parser],
        card_type: bank[:card_type],
        sort_order: bank[:sort_order],
        enabled: true
      )
    end

    migrate_legacy_bank_codes
  end

  def down
    drop_table :mail_sync_bank_links
    remove_column :mail_bank_formats, :card_type
  end

  private

    def migrate_legacy_bank_codes
      MailSyncConnection.find_each do |connection|
        next if MailSyncBankLink.exists?(mail_sync_connection_id: connection.id)

        Array(connection.bank_codes).each do |code|
          format = MailBankFormat.find_by(code: code.to_s.upcase)
          next unless format

          account = find_legacy_account(connection.family, format)
          next unless account

          MailSyncBankLink.create!(
            mail_sync_connection: connection,
            mail_bank_format: format,
            account: account
          )
        end
      end
    end

    def find_legacy_account(family, format)
      keywords = MailBankFormat::ACCOUNT_MATCHERS[format.code] || [ format.code ]
      family.accounts.visible.alphabetically.find do |account|
        name = account.name.upcase
        keywords.any? { |keyword| name.include?(keyword) }
      end
    end
end
