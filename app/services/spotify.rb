module Spotify
  # Raised for any non-success response from the Spotify API.
  class Error < StandardError
    attr_reader :status, :body

    def initialize(message, status: nil, body: nil)
      @status = status
      @body = body
      super(message)
    end
  end

  # The stored token was rejected (revoked, or scopes changed) — reconnect needed.
  class AuthError < Error; end

  # Spotify asked us to back off.
  class RateLimitedError < Error
    attr_reader :retry_after

    def initialize(message, retry_after: nil, **opts)
      @retry_after = retry_after
      super(message, **opts)
    end
  end

  # No account has been linked yet.
  class NotConnectedError < Error; end

  SCOPES = %w[user-read-recently-played].freeze

  class << self
    def client_id
      setting(:client_id)
    end

    def client_secret
      setting(:client_secret)
    end

    def redirect_uri
      setting(:redirect_uri) || "http://127.0.0.1:3000/spotify/callback"
    end

    def configured?
      client_id.present? && client_secret.present?
    end

    private

    def setting(key)
      ENV["SPOTIFY_#{key.to_s.upcase}"].presence ||
        Rails.application.credentials.dig(:spotify, key).presence
    end
  end
end
