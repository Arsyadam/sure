module MailSync
  class Configuration
    GMAIL_SCOPES = [
      "https://www.googleapis.com/auth/gmail.readonly",
      "https://www.googleapis.com/auth/gmail.modify"
    ].freeze

    class << self
      def configured?
        google_client_id.present? && google_client_secret.present? && llm_api_key.present? && push_configured?
      end

      def push_configured?
        gmail_pubsub_topic.present?
      end

      def gmail_pubsub_topic
        ENV["MAIL_SYNC_GMAIL_PUBSUB_TOPIC"].presence
      end

      def gmail_webhook_url
        ENV["MAIL_SYNC_GMAIL_WEBHOOK_URL"].presence
      end

      def google_client_id
        ENV["MAIL_SYNC_GOOGLE_CLIENT_ID"].presence || ENV["GOOGLE_CLIENT_ID"].presence
      end

      def google_client_secret
        ENV["MAIL_SYNC_GOOGLE_CLIENT_SECRET"].presence || ENV["GOOGLE_CLIENT_SECRET"].presence
      end

      def llm_api_url
        ENV.fetch("MAIL_SYNC_LLM_API_URL", "https://9router.arsyadam.id/v1/chat/completions")
      end

      def llm_api_key
        ENV["MAIL_SYNC_LLM_API_KEY"].presence || ENV["LLM_API_KEY"].presence
      end

      def llm_model
        ENV.fetch("MAIL_SYNC_LLM_MODEL", ENV.fetch("LLM_MODEL", "gc/gemini-3-flash-preview"))
      end

      def oauth_redirect_uri
        ENV["MAIL_SYNC_OAUTH_REDIRECT_URI"].presence
      end
    end
  end
end
