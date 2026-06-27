class MailSyncConnection < ApplicationRecord
  include Encryptable

  belongs_to :family
  belongs_to :user
  has_many :processed_messages,
           class_name: "MailSyncProcessedMessage",
           dependent: :destroy,
           inverse_of: :mail_sync_connection
  has_many :events,
           class_name: "MailSyncEvent",
           dependent: :destroy,
           inverse_of: :mail_sync_connection
  has_many :bank_links,
           class_name: "MailSyncBankLink",
           dependent: :destroy,
           inverse_of: :mail_sync_connection
  has_many :linked_bank_formats, through: :bank_links, source: :mail_bank_format

  if encryption_ready?
    encrypts :refresh_token
  end

  validates :gmail_email, presence: true
  validates :refresh_token, presence: true
  validates :sync_from_at, presence: true
  validate :bank_codes_are_known

  scope :active, -> { where(enabled: true) }

  def selected_bank_codes
    if bank_links.any?
      bank_links.joins(:mail_bank_format).distinct.pluck("mail_bank_formats.code")
    else
      Array(bank_codes).map(&:to_s).map(&:upcase).reject(&:blank?)
    end
  end

  def linked_format?(bank_format)
    bank_links.exists?(mail_bank_format_id: bank_format.id)
  end

  def resolve_account_for_format(bank_format, html:)
    return nil unless linked_format?(bank_format)

    hints = MailSync::AccountHintExtractor.extract(html)
    candidates = family.accounts.visible
      .where(accountable_type: bank_format.required_account_type)
      .where(mail_bank_format_id: [ bank_format.id, nil ])

    if hints.any?
      matched = candidates.where(account_number_last4: hints)
      return matched.first if matched.one?

      return nil if matched.many?
    end

    with_mask = candidates.where.not(account_number_last4: [ nil, "" ])
    return with_mask.first if with_mask.one? && hints.empty?

    nil
  end

  def message_processed?(gmail_message_id)
    processed_messages.exists?(gmail_message_id: gmail_message_id)
  end

  # Atomic claim — only one worker may process a Gmail message_id.
  def claim_message!(gmail_message_id)
    processed_messages.create!(gmail_message_id: gmail_message_id)
    true
  rescue ActiveRecord::RecordNotUnique
    false
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors[:gmail_message_id].any? ? false : raise
  end

  def release_message_claim!(gmail_message_id)
    processed_messages.where(gmail_message_id: gmail_message_id).delete_all
  end

  def mark_message_processed!(gmail_message_id)
    claim_message!(gmail_message_id)
  end

  private

    def bank_codes_are_known
      return if bank_codes.blank?

      known = MailBankFormat.pluck(:code).map(&:upcase)
      unknown = selected_bank_codes - known
      return if unknown.empty?

      errors.add(:bank_codes, "contains unknown banks: #{unknown.join(', ')}")
    end
end
