class AddInstitutionToMailBankFormats < ActiveRecord::Migration[7.2]
  BANKS = [
    {
      code: "BCA",
      sender_email: "kartu@bca.co.id",
      institution_name: "BCA",
      institution_domain: "bca.co.id"
    },
    {
      code: "CIMB",
      sender_email: "octo-noreply@cimbniaga.co.id",
      institution_name: "CIMB Niaga",
      institution_domain: "cimbniaga.co.id"
    },
    {
      code: "JAGO",
      sender_email: "noreply@jago.com",
      institution_name: "Bank Jago",
      institution_domain: "bankjago.co.id"
    },
    {
      code: "GOPAY",
      sender_email: "receipts@gotagihan.gojek.com",
      institution_name: "GoPay",
      institution_domain: "gojek.com"
    },
    {
      code: "MANDIRI",
      sender_email: "noreply.livin@bankmandiri.co.id",
      institution_name: "Bank Mandiri",
      institution_domain: "bankmandiri.co.id"
    },
    {
      code: "JENIUS_CC",
      sender_email: "jenius_noreply@smbci.com",
      institution_name: "Jenius",
      institution_domain: "jenius.com"
    },
    {
      code: "MEGA_CC",
      sender_email: "notifikasi.kartukredit@bankmega.com",
      institution_name: "Bank Mega",
      institution_domain: "bankmega.com"
    }
  ].freeze

  def up
    add_column :mail_bank_formats, :institution_name, :string
    add_column :mail_bank_formats, :institution_domain, :string

    BANKS.each do |bank|
      format = MailBankFormat.find_by(code: bank[:code])
      next unless format

      attrs = {
        institution_name: bank[:institution_name],
        institution_domain: bank[:institution_domain]
      }
      attrs[:sender_email] = bank[:sender_email] if format.sender_email.blank?
      format.update!(attrs)
    end
  end

  def down
    remove_column :mail_bank_formats, :institution_domain
    remove_column :mail_bank_formats, :institution_name
  end
end
