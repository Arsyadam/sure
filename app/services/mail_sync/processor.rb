module MailSync
  class Processor
    def initialize(connection)
      @connection = connection
      @family = connection.family
    end

    def process_from_push!(history_id:)
      unless Configuration.configured?
        EventLogger.log("push.skipped", "Mail sync not configured", level: "warn", connection: @connection)
        return
      end
      unless @connection.enabled?
        EventLogger.log("push.skipped", "Connection disabled", level: "warn", connection: @connection)
        return
      end

      @connection.with_lock do
        @connection.reload
        history_id = history_id.to_s
        stored = @connection.gmail_history_id.to_s

        if stored.blank?
          @connection.update!(gmail_history_id: history_id, last_synced_at: Time.current)
          EventLogger.log(
            "push.baseline",
            "Set initial history pointer to #{history_id}",
            connection: @connection,
            history_id: history_id
          )
          return
        end

        if history_id.to_i <= stored.to_i
          EventLogger.log(
            "push.noop",
            "Already processed history #{history_id} (stored #{stored})",
            connection: @connection,
            history_id: history_id
          )
          return
        end

        formats = enabled_formats
        if formats.empty?
          EventLogger.log("push.skipped", "No enabled bank formats", level: "warn", connection: @connection)
          return
        end

        gmail = GmailClient.new(refresh_token: @connection.refresh_token)
        accounts = @family.accounts.to_a
        categories = @family.categories.expenses.to_a

        processed_count = sync_history_messages(gmail, stored, accounts, categories, formats)
        @connection.update!(gmail_history_id: history_id, last_synced_at: Time.current)

        EventLogger.log(
          "push.completed",
          "History #{stored} → #{history_id}, scanned messages",
          connection: @connection,
          history_id: history_id,
          messages_scanned: processed_count
        )
      end
    rescue => e
      if history_expired?(e)
        EventLogger.log(
          "push.history_expired",
          "Resetting history pointer to #{history_id}",
          level: "warn",
          connection: @connection,
          history_id: history_id
        )
        @connection.update!(gmail_history_id: history_id, last_synced_at: Time.current)
      else
        EventLogger.log("push.error", e.message, level: "error", connection: @connection, history_id: history_id)
        raise
      end
    end

    private

      def enabled_formats
        if @connection.bank_links.any?
          format_ids = @connection.bank_links.distinct.pluck(:mail_bank_format_id)
          MailBankFormat.enabled.where(id: format_ids).ordered.to_a
        else
          codes = @connection.selected_bank_codes
          codes = MailBankFormat.enabled.pluck(:code) if codes.empty?
          MailBankFormat.enabled.where(code: codes).ordered.to_a
        end
      end

      def sync_history_messages(gmail, start_history_id, accounts, categories, formats)
        page_token = nil
        scanned = 0

        loop do
          data = gmail.list_history(start_history_id: start_history_id, page_token: page_token)
          Array(data["history"]).each do |record|
            Array(record["messagesAdded"]).each do |added|
              message_id = added.dig("message", "id")
              next if message_id.blank?

              scanned += 1
              process_message(
                gmail,
                message_id,
                accounts,
                categories,
                formats,
                history_context: {
                  history_record_id: record["id"],
                  thread_id: added.dig("message", "threadId"),
                  label_ids: added.dig("message", "labelIds")
                }
              )
            end
          end

          page_token = data["nextPageToken"]
          break if page_token.blank?
        end

        scanned
      end

      def process_message(gmail, message_id, accounts, categories, formats, history_context: {})
        return unless @connection.claim_message!(message_id)

        message = gmail.fetch_message(message_id)
        received_at = gmail.message_received_at(message)
        from = gmail.from_header(message)

        if received_at.present? && received_at < @connection.sync_from_at
          EventLogger.log(
            "message.skipped",
            "Email too old (#{received_at.iso8601})",
            connection: @connection,
            message_id: message_id,
            from: from
          )
          return
        end

        bank_format = MailBankFormat.find_by_sender(from)
        unless bank_format
          EventLogger.log(
            "message.ignored",
            "Unknown sender #{from}",
            connection: @connection,
            message_id: message_id,
            from: from
          )
          return
        end
        unless formats.any? { |f| f.id == bank_format.id }
          EventLogger.log(
            "message.ignored",
            "#{bank_format.code} not in bank selection",
            connection: @connection,
            message_id: message_id,
            from: from
          )
          return
        end

        html = gmail.html_body_from_message(message)
        parsed = BankEmailParser.parse(html, bank_format: bank_format)

        account = match_account(bank_format, html: html)
        unless account
          hints = MailSync::AccountHintExtractor.extract(html)
          hint_msg = hints.any? ? " (last 4 in email: #{hints.join(', ')})" : ""
          raise StandardError,
                "No matching account for #{bank_format.code}#{hint_msg}. " \
                "Enable this bank in Bank Sync and set the last 4 digits on each account under Accounts → Additional details."
        end

        resolved = CategoryResolver.new(parsed: parsed, categories: categories).resolve
        merchant_name = resolved[:merchant].presence || parsed.transaction_type.presence || bank_format.name

        if account.entries.exists?(source: TransactionCreator::SOURCE, external_id: message_id)
          return
        end

        TransactionCreator.new(
          family: @family,
          account: account,
          category: resolved[:category],
          name: merchant_name,
          amount: resolved[:amount],
          date: resolved[:date],
          gmail_message_id: message_id
        ).create!

        gmail.mark_as_read(message_id)

        EventLogger.log(
          "transaction.created",
          "#{merchant_name} Rp #{resolved[:amount]} → #{resolved[:category].name}",
          connection: @connection,
          message_id: message_id,
          from: from,
          bank: bank_format.code,
          merchant: merchant_name,
          amount: resolved[:amount],
          category: resolved[:category].name
        )
      rescue => e
        if message_not_found?(e)
          trace = trace_missing_message(gmail, message_id, history_context)
          EventLogger.log(
            "message.skipped",
            "Email no longer in mailbox (Gmail 404)",
            level: "warn",
            connection: @connection,
            message_id: message_id,
            from: from,
            **trace
          )
        elsif duplicate_entry?(e)
          nil
        else
          @connection.release_message_claim!(message_id)
          EventLogger.log(
            "message.failed",
            e.message,
            level: "error",
            connection: @connection,
            message_id: message_id,
            from: from,
            **history_context
          )
        end
      end

      def match_account(bank_format, html:)
        @connection.resolve_account_for_format(bank_format, html: html)
      end

      def history_expired?(error)
        error.message.match?(/historyId|not found|404/i)
      end

      def message_not_found?(error)
        error.message.match?(/requested entity was not found/i)
      end

      def duplicate_entry?(error)
        error.message.match?(/external has already been taken/i)
      end

      def trace_missing_message(gmail, message_id, history_context)
        meta = {}
        begin
          meta = gmail.fetch_message_metadata(message_id)
        rescue => e
          meta = { metadata_error: e.message }
        end

        {
          history_record_id: history_context[:history_record_id],
          thread_id: history_context[:thread_id] || meta[:thread_id],
          label_ids: history_context[:label_ids] || meta[:label_ids],
          subject: meta[:subject],
          metadata_from: meta[:from]
        }.compact
      end
  end
end
