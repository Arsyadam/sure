class UpdateGopaySenderEmail < ActiveRecord::Migration[7.2]
  def up
    format = MailBankFormat.find_by(code: "GOPAY")
    return unless format

    format.update!(
      sender_email: "receipts@gotagihan.gojek.com",
      name: "GoPay / GoTagihan",
      description: "Email notifikasi dari receipts@gotagihan.gojek.com (pulsa, paket data, tagihan)"
    )
  end

  def down
    format = MailBankFormat.find_by(code: "GOPAY")
    return unless format

    format.update!(
      sender_email: "no-reply@customers.go-pay.co.id",
      name: "GoPay",
      description: "Email notifikasi dari no-reply@customers.go-pay.co.id"
    )
  end
end
