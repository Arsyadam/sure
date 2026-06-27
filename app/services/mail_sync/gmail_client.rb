module MailSync
  class GmailClient
    TOKEN_URL = "https://oauth2.googleapis.com/token"
    GMAIL_API = "https://gmail.googleapis.com/gmail/v1"

    def initialize(refresh_token:)
      @refresh_token = refresh_token
    end

    def self.authorization_url(state:, redirect_uri:)
      params = {
        client_id: Configuration.google_client_id,
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: Configuration::GMAIL_SCOPES.join(" "),
        access_type: "offline",
        prompt: "consent",
        state: state
      }
      "https://accounts.google.com/o/oauth2/v2/auth?#{URI.encode_www_form(params)}"
    end

    def self.exchange_code(code:, redirect_uri:)
      response = Faraday.post(TOKEN_URL) do |req|
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(
          code: code,
          client_id: Configuration.google_client_id,
          client_secret: Configuration.google_client_secret,
          redirect_uri: redirect_uri,
          grant_type: "authorization_code"
        )
      end
      parse_token_response(response)
    end

    def fetch_profile_email
      data = gmail_get("users/me/profile")
      data["emailAddress"]
    end

    def list_new_messages(sender_emails:, after:, max_results: 20)
      query = build_query(sender_emails, after: after)
      data = gmail_get("users/me/messages", q: query, maxResults: max_results)
      Array(data["messages"])
    end

    def start_watch(topic_name:)
      Rails.logger.debug("[MailSync] gmail.start_watch topic=#{topic_name}")
      response = gmail_post("users/me/watch", topicName: topic_name, labelIds: [ "INBOX" ])
      Rails.logger.debug("[MailSync] gmail.start_watch ok historyId=#{response['historyId']} expiration=#{response['expiration']}")
      response
    end

    def stop_watch
      gmail_post("users/me/stop", {})
    end

    def list_history(start_history_id:, page_token: nil, max_results: 100)
      Rails.logger.debug("[MailSync] gmail.list_history from=#{start_history_id} page=#{page_token || 'none'}")
      data = gmail_get(
        "users/me/history",
        startHistoryId: start_history_id,
        historyTypes: "messageAdded",
        maxResults: max_results,
        pageToken: page_token
      )
      count = Array(data["history"]).sum { |r| Array(r["messagesAdded"]).size }
      Rails.logger.debug("[MailSync] gmail.list_history ok messages_added=#{count}")
      data
    end

    def message_received_at(message)
      ms = message["internalDate"].to_i
      return nil if ms.zero?

      Time.at(ms / 1000.0)
    end

    def fetch_message(message_id)
      Rails.logger.debug("[MailSync] gmail.fetch_message id=#{message_id}")
      gmail_get("users/me/messages/#{message_id}", format: "full")
    end

    def fetch_message_metadata(message_id)
      Rails.logger.debug("[MailSync] gmail.fetch_message_metadata id=#{message_id}")
      message = gmail_get("users/me/messages/#{message_id}", format: "metadata")
      headers = message.dig("payload", "headers") || []
      {
        from: headers.find { |h| h["name"].casecmp?("From") }&.dig("value"),
        subject: headers.find { |h| h["name"].casecmp?("Subject") }&.dig("value"),
        date: headers.find { |h| h["name"].casecmp?("Date") }&.dig("value"),
        label_ids: message["labelIds"],
        thread_id: message["threadId"]
      }
    end

    def message_missing?(error)
      error.message.match?(/requested entity was not found/i)
    end

    def fetch_message_html(message_id)
      html_body_from_message(fetch_message(message_id))
    end

    def html_body_from_message(message)
      extract_html_body(message)
    end

    def from_header(message)
      header_value(message, "From")
    end

    def mark_as_read(message_id)
      gmail_post("users/me/messages/#{message_id}/modify", removeLabelIds: [ "UNREAD" ])
    end

    private

      def build_query(sender_emails, after: nil)
        emails = Array(sender_emails).map(&:to_s).map(&:strip).reject(&:blank?).uniq
        parts = []
        parts << "after:#{after.strftime('%Y/%m/%d')}" if after.present?
        if emails.empty?
          parts << "is:unread"
        else
          from_filters = emails.map { |email| "from:#{email}" }.join(" OR ")
          parts << "(#{from_filters})"
        end
        parts.join(" ")
      end

      def header_value(message, name)
        headers = message.dig("payload", "headers") || []
        headers.find { |h| h["name"].casecmp?(name) }&.dig("value")
      end

      def access_token
        @access_token ||= refresh_access_token
      end

      def refresh_access_token
        response = Faraday.post(TOKEN_URL) do |req|
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          req.body = URI.encode_www_form(
            client_id: Configuration.google_client_id,
            client_secret: Configuration.google_client_secret,
            refresh_token: @refresh_token,
            grant_type: "refresh_token"
          )
        end
        body = parse_token_response(response)
        body["access_token"]
      end

      def self.parse_token_response(response)
        body = JSON.parse(response.body)
        unless response.success?
          raise StandardError, body["error_description"] || body["error"] || "OAuth token error"
        end
        body
      end

      def parse_token_response(response)
        self.class.parse_token_response(response)
      end

      def gmail_get(path, params = {})
        query = URI.encode_www_form(params.compact) if params.present?
        url = "#{GMAIL_API}/#{path}"
        url = "#{url}?#{query}" if query.present?

        response = Faraday.get(url) do |req|
          req.headers["Authorization"] = "Bearer #{access_token}"
        end
        parse_gmail_response(response)
      end

      def gmail_post(path, payload)
        response = Faraday.post("#{GMAIL_API}/#{path}") do |req|
          req.headers["Authorization"] = "Bearer #{access_token}"
          req.headers["Content-Type"] = "application/json"
          req.body = payload.to_json
        end
        parse_gmail_response(response)
      end

      def parse_gmail_response(response)
        body = JSON.parse(response.body)
        unless response.success?
          msg = body.dig("error", "message") || "Gmail API error (#{response.status})"
          Rails.logger.error("[MailSync] gmail.api_error status=#{response.status} message=#{msg}")
          raise StandardError, msg
        end
        body
      end

      def extract_html_body(message)
        html = find_html_part(message["payload"] || {})
        return html if html.present?

        nil
      end

      def find_html_part(part)
        if part["mimeType"] == "text/html" && part.dig("body", "data").present?
          return decode_body_data(part.dig("body", "data"))
        end

        Array(part["parts"]).each do |child|
          html = find_html_part(child)
          return html if html.present?
        end

        if part.dig("body", "data").present? && part["mimeType"].to_s.start_with?("text/html")
          return decode_body_data(part.dig("body", "data"))
        end

        nil
      end

      def decode_body_data(data)
        Base64.urlsafe_decode64(data.tr("-_", "+/"))
      rescue ArgumentError
        Base64.decode64(data)
      end
  end
end
