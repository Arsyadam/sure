class MailSyncBankLink < ApplicationRecord
  belongs_to :mail_sync_connection
  belongs_to :mail_bank_format

  validates :mail_bank_format_id, uniqueness: { scope: :mail_sync_connection_id }
end
