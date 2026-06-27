class MailSyncProcessedMessage < ApplicationRecord
  belongs_to :mail_sync_connection, inverse_of: :processed_messages

  validates :gmail_message_id, presence: true,
            uniqueness: { scope: :mail_sync_connection_id }
end
