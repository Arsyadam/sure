class AddMailBankFormatToAccounts < ActiveRecord::Migration[7.2]
  def change
    add_reference :accounts, :mail_bank_format, null: true, foreign_key: true, type: :uuid
  end
end
