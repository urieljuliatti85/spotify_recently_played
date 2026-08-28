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

  # Spotify has no such track/artist any more.
  class NotFoundError < Error; end

  # No account has been linked yet.
  class NotConnectedError < Error; end

  # Spotify never answered at all — DNS, connection refused, or the request
  # timed out. Distinct from a non-2xx response, which at least means
  # something on the other end is alive to have said no.
  class UnreachableError < Error; end

  # What the owner grants: their history, the playlists the site lists, the
  # one the playlists tab can build for them (`-public` is the narrower of the
  # two write scopes and the only one this app needs, because the playlist it
  # creates has to be public to show up on the tab at all), and their
  # algorithmic top artists/tracks for the Overview's "Top Items" box.
  SCOPES = %w[
    user-read-recently-played
    playlist-read-private
    playlist-modify-public
    user-top-read
  ].freeze
  # What a friend grants. The playlists tab only ever shows the owner's, so
  # asking a friend for their private ones would be taking more than the site
  # can use.
  FRIEND_SCOPES = %w[user-read-recently-played].freeze

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

    # The country the catalogue should be judged against. Spotify only reports
    # whether a track is playable when it is told a market, and it only reveals
    # the owner's own country under `user-read-private`, which this app does not
    # ask for — so SPOTIFY_MARKET is the way to set one without widening the
    # consent screen for every listener. Without a market, playability comes
    # back unknown and is taken at face value.
    def market
      return ENV["SPOTIFY_MARKET"].presence.to_s.upcase.presence if ENV["SPOTIFY_MARKET"].present?

      Rails.cache.fetch("spotify:market", expires_in: 12.hours) do
        Client.new.me&.dig("country").presence
      end
    rescue Error
      nil
    end

    private

    def setting(key)
      ENV["SPOTIFY_#{key.to_s.upcase}"].presence ||
        Rails.application.credentials.dig(:spotify, key).presence
    end
  end
end
