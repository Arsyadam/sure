class BackfillMailBankFormatSenderEmails < ActiveRecord::Migration[7.2]
  SENDERS = {
    "BCA" => "kartu@bca.co.id",
    "CIMB" => "octo-noreply@cimbniaga.co.id",
    "JAGO" => "noreply@jago.com",
    "GOPAY" => "receipts@gotagihan.gojek.com",
    "MANDIRI" => "noreply.livin@bankmandiri.co.id",
    "JENIUS_CC" => "jenius_noreply@smbci.com",
    "MEGA_CC" => "notifikasi.kartukredit@bankmega.com"
  }.freeze

  def up
    SENDERS.each do |code, sender|
      format = MailBankFormat.find_by(code: code)
      next unless format
      next if format.sender_email.present?

      format.update!(sender_email: sender)
    end
  end

  def down
  end
end
