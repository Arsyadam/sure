class MailSyncEvent < ApplicationRecord
  LEVELS = %w[info warn error].freeze

  belongs_to :mail_sync_connection, optional: true

  validates :level, inclusion: { in: LEVELS }
  validates :event, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_connection, ->(connection) { where(mail_sync_connection: connection) }
  scope :issues, -> { where(level: %w[warn error]) }
  scope :imports, -> { where(event: "transaction.created") }

  def self.log!(event:, message: nil, level: "info", connection: nil, metadata: {})
    record = create!(
      mail_sync_connection: connection,
      event: event.to_s,
      message: message,
      level: level,
      metadata: metadata
    )
    meta = metadata.present? ? " #{metadata.to_json}" : ""
    line = "[MailSync] #{event}#{message.present? ? " — #{message}" : ""}#{meta}"
    case level
    when "error" then Rails.logger.error(line)
    when "warn" then Rails.logger.warn(line)
    else Rails.logger.debug(line)
    end
    record
  end
end
