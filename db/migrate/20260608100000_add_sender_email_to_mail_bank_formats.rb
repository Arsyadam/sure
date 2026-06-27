class AddSenderEmailToMailBankFormats < ActiveRecord::Migration[7.2]
  BANKS = [
    { code: "BCA", sender: "bca@bca.co.id", name: "BCA (myBCA)", parser: "bca", sort_order: 1,
      description: "Email notifikasi dari bca@bca.co.id" },
    { code: "CIMB", sender: "octo-noreply@cimbniaga.co.id", name: "CIMB Niaga / OCTO", parser: "cimb", sort_order: 2,
      description: "Email notifikasi dari octo-noreply@cimbniaga.co.id" },
    { code: "JAGO", sender: "noreply@jago.com", name: "Bank Jago", parser: "jago", sort_order: 3,
      description: "Email notifikasi dari noreply@jago.com" },
    { code: "GOPAY", sender: "receipts@gotagihan.gojek.com", name: "GoPay / GoTagihan", parser: "gopay", sort_order: 4,
      description: "Email notifikasi dari receipts@gotagihan.gojek.com (pulsa, paket data, tagihan)" }
  ].freeze

  def up
    add_column :mail_bank_formats, :sender_email, :string

    BANKS.each do |bank|
      format = MailBankFormat.find_by(code: bank[:code])
      if format
        format.update!(
          sender_email: bank[:sender],
          name: bank[:name],
          description: bank[:description],
          parser: bank[:parser],
          sort_order: bank[:sort_order],
          enabled: true
        )
      else
        MailBankFormat.create!(
          code: bank[:code],
          sender_email: bank[:sender],
          name: bank[:name],
          description: bank[:description],
          parser: bank[:parser],
          sort_order: bank[:sort_order],
          enabled: true
        )
      end
    end

    change_column_null :mail_bank_formats, :sender_email, false
    add_index :mail_bank_formats, :sender_email, unique: true
  end

  def down
    remove_index :mail_bank_formats, :sender_email
    remove_column :mail_bank_formats, :sender_email
  end
end
