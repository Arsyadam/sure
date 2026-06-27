module MailSync
  class PubsubVerifier
    GOOGLE_CERTS_URL = "https://www.googleapis.com/oauth2/v3/certs"
    ISSUERS = [ "accounts.google.com", "https://accounts.google.com" ].freeze

    def self.verify!(token, audience:)
      if skip_verification?
        Rails.logger.warn("[MailSync] pubsub.verify skipped (MAIL_SYNC_PUBSUB_VERIFY=false)")
        return true
      end

      raise StandardError, "Missing Pub/Sub auth token" if token.blank?

      payload, = JWT.decode(
        token,
        nil,
        true,
        {
          algorithms: [ "RS256" ],
          iss: ISSUERS,
          verify_iss: true,
          aud: audience,
          verify_aud: true,
          jwks: jwks
        }
      )

      Rails.logger.debug("[MailSync] pubsub.verify ok sub=#{payload['sub']} aud=#{payload['aud']}")
      payload
    rescue JWT::DecodeError => e
      Rails.logger.error("[MailSync] pubsub.verify failed: #{e.message}")
      raise
    end

    def self.skip_verification?
      default = Rails.env.production? ? "true" : "false"
      !ActiveModel::Type::Boolean.new.cast(ENV.fetch("MAIL_SYNC_PUBSUB_VERIFY", default))
    end

    def self.jwks
      @jwks ||= begin
        response = Faraday.get(GOOGLE_CERTS_URL)
        raise StandardError, "Failed to fetch Google JWKS" unless response.success?

        JWT::JWK::Set.new(JSON.parse(response.body))
      end
    end
  end
end
