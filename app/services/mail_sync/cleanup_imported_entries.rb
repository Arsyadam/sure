module MailSync
  class CleanupImportedEntries
    MAIL_SYNC_SOURCE = "mail_sync"

    def initialize(connection)
      @connection = connection
      @family = connection.family
    end

    def cleanup!
      deleted = 0
      deleted += delete_tagged_entries
      deleted += delete_legacy_bulk_import
      @connection.processed_messages.delete_all
      deleted
    end

    private

      def delete_tagged_entries
        scope = Entry.joins(:account)
                     .where(accounts: { family_id: @family.id })
                     .where(source: MAIL_SYNC_SOURCE)
        count = scope.count
        scope.find_each(&:destroy)
        count
      end

      def delete_legacy_bulk_import
        account_ids = bank_account_ids
        return 0 if account_ids.empty?

        scope = Entry.joins(:account)
                     .where(accounts: { id: account_ids })
                     .where(entryable_type: "Transaction")
                     .where("entries.created_at >= ?", @connection.created_at)
                     .where("entries.source IS NULL")

        count = scope.count
        scope.find_each(&:destroy)
        count
      end

      def bank_account_ids
        keywords = MailBankFormat.pluck(:code).flat_map do |code|
          MailBankFormat::ACCOUNT_MATCHERS[code] || [ code ]
        end.map(&:upcase).uniq

        @family.accounts.select do |account|
          name = account.name.upcase
          keywords.any? { |keyword| name.include?(keyword) }
        end.map(&:id)
      end
  end
end
