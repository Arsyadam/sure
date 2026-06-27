module MailSync
  # Debug a Gmail message_id: API fetch, DB events, processed flag.
  class MessageTracer
    def initialize(connection)
      @connection = connection
      @gmail = GmailClient.new(refresh_token: connection.refresh_token)
      @errors = []
    end

    def trace(message_id)
      message_id = message_id.to_s
      lines = []
      lines << "message_id=#{message_id}"
      lines << "connection=#{@connection.gmail_email}"
      lines << "processed=#{@connection.message_processed?(message_id)}"
      lines << "entry=#{Entry.find_by(source: TransactionCreator::SOURCE, external_id: message_id)&.id || 'none'}"

      events = MailSyncEvent.for_connection(@connection)
        .where("metadata->>'message_id' = ?", message_id)
        .order(created_at: :desc)
        .limit(10)
      lines << "events=#{events.count}"
      events.each do |e|
        lines << "  [#{e.created_at}] #{e.level} #{e.event}: #{e.message} #{e.metadata.to_json}"
      end

      lines << "--- gmail metadata ---"
      meta = fetch { @gmail.fetch_message_metadata(message_id) }
      if meta
        lines << "from=#{meta[:from].inspect}"
        lines << "subject=#{meta[:subject].inspect}"
        lines << "date=#{meta[:date].inspect}"
        lines << "labelIds=#{meta[:label_ids].inspect}"
        lines << "threadId=#{meta[:thread_id].inspect}"
      else
        lines << "(metadata unavailable)"
      end

      lines << "--- gmail full ---"
      full = fetch { @gmail.fetch_message(message_id) }
      if full
        html = @gmail.html_body_from_message(full)
        text = html.to_s.gsub(/<[^>]+>/, " ").squish
        lines << "snippet=#{text.truncate(400)}"
      else
        lines << "(full message unavailable — likely deleted or never persisted)"
      end

      @errors.each { |err| lines << err }
      lines.join("\n")
    end

    def trace_history(start_history_id)
      start_history_id = start_history_id.to_s
      lines = ["history from=#{start_history_id}", "---"]
      page_token = nil

      loop do
        data = fetch { @gmail.list_history(start_history_id: start_history_id, page_token: page_token) }
        break unless data

        Array(data["history"]).each do |record|
          Array(record["messagesAdded"]).each do |added|
            msg = added["message"] || {}
            lines << [
              "historyRecord=#{record['id']}",
              "messageId=#{msg['id']}",
              "threadId=#{msg['threadId']}",
              "labels=#{Array(msg['labelIds']).join(',')}"
            ].join(" ")
          end
        end

        page_token = data["nextPageToken"]
        break if page_token.blank?
      end

      @errors.each { |err| lines << err }
      lines.join("\n")
    end

    private

      def fetch
        yield
      rescue => e
        @errors << "ERROR: #{e.message}"
        nil
      end
  end
end
