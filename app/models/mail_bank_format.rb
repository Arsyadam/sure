class MailBankFormat < ApplicationRecord
  PARSERS = %w[bca cimb jago gopay mandiri jenius_credit mega_credit].freeze
  CARD_TYPES = %w[debit credit ewallet].freeze

  ACCOUNT_MATCHERS = {
    "BCA" => %w[BCA],
    "CIMB" => %w[CIMB OCTO],
    "JAGO" => %w[JAGO],
    "GOPAY" => %w[GOPAY GOJEK GO-PAY GOTAGIHAN],
    "MANDIRI" => %w[MANDIRI LIVIN],
    "JENIUS_CC" => %w[JENIUS D-CARD DCARD],
    "MEGA_CC" => %w[MEGA]
  }.freeze

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true
  validates :sender_email, presence: true, uniqueness: { case_sensitive: false }
  validates :parser, presence: true, inclusion: { in: PARSERS }
  validates :card_type, presence: true, inclusion: { in: CARD_TYPES }

  before_validation :normalize_code
  before_validation :normalize_sender_email

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:sort_order, :name) }

  scope :for_accountable_type, ->(accountable_type) {
    if accountable_type.to_s == "CreditCard"
      enabled.where(card_type: "credit")
    else
      enabled.where(card_type: %w[debit ewallet])
    end
  }

  PATTERN_FIELDS = %w[merchant amount date transaction_type status].freeze

  def patterns_enabled?
    patterns.is_a?(Hash) && PATTERN_FIELDS.any? { |field| patterns[field].present? }
  end

  def self.find_by_sender(from_header)
    email = extract_email(from_header)
    return nil if email.blank?

    find_by(sender_email: email.downcase)
  end

  def self.extract_email(from_header)
    raw = from_header.to_s.strip
    raw[/<([^>]+)>/, 1]&.downcase || raw.downcase
  end

  def account_keywords
    ACCOUNT_MATCHERS[code.to_s.upcase] || [ code.to_s.upcase ]
  end

  def credit?
    card_type == "credit"
  end

  def required_account_type
    credit? ? "CreditCard" : "Depository"
  end

  def card_type_label
    I18n.t("settings.bank_sync.card_types.#{card_type}", default: card_type.humanize)
  end

  def select_label
    if sender_email.present?
      "#{name} (#{sender_email})"
    else
      name
    end
  end

  def institution_json
    {
      institution_name: institution_name.presence || name,
      institution_domain: institution_domain
    }
  end

  private

    def normalize_code
      self.code = code.to_s.strip.upcase if code.present?
    end

    def normalize_sender_email
      self.sender_email = sender_email.to_s.strip.downcase if sender_email.present?
    end
end
