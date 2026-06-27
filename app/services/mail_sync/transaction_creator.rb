module MailSync
  class TransactionCreator
    SOURCE = "mail_sync"

    def initialize(family:, account:, category:, name:, amount:, date:, gmail_message_id:)
      @family = family
      @account = account
      @category = category
      @name = name
      @amount = amount
      @date = date
      @gmail_message_id = gmail_message_id
    end

    def create!
      entry = @account.entries.new(
        name: @name,
        date: parsed_date,
        amount: @amount.to_f.abs,
        currency: @family.currency,
        source: SOURCE,
        external_id: @gmail_message_id,
        entryable_type: "Transaction",
        entryable_attributes: {
          category_id: @category.id
        }
      )

      unless entry.save
        raise StandardError, entry.errors.full_messages.join(", ")
      end

      entry.sync_account_later
      entry.lock_saved_attributes!
      entry.transaction
    end

    private

      def parsed_date
        return Date.current if @date.blank?

        Date.parse(@date.to_s)
      rescue Date::Error
        Date.current
      end
  end
end
