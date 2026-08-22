require "net/http"

module Spotify
  # Thin wrapper around the Spotify Web API, scoped to the linked account.
  class Client
    API_HOST = "https://api.spotify.com".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    # The OAuth callback has to ask who just authorized before it can know
    # which row to write the tokens onto, so it needs a client backed by a bare
    # token rather than by a stored account.
    BareToken = Struct.new(:access_token) do
      def fresh_access_token = access_token
    end

    def self.with_token(access_token)
      new(BareToken.new(access_token))
    end

    def initialize(account = SpotifyAccount.owner)
      raise NotConnectedError, "No Spotify account linked yet" if account.nil?

      @account = account
    end

    # Spotify keeps only the last 50 plays, so we poll often and accumulate
    # the history locally. `after` is a Time; only later plays are returned.
    def recently_played(limit: 50, after: nil)
      params = { limit: limit.clamp(1, 50) }
      params[:after] = (after.to_f * 1000).round if after

      get("/v1/me/player/recently-played", params)
    end

    def me
      get("/v1/me")
    end

    # Full track objects, including each artist's id. The plays feed only
    # carries simplified ones, so backfilling credits means asking again.
    def tracks(ids)
      fetch_each("/v1/tracks", ids)
    end

    # Artist objects carry the photos that simplified ones inside a track do
    # not, which is the only place a real artist image comes from.
    def artists(ids)
      fetch_each("/v1/artists", ids)
    end

    def artist_top_tracks(id, market: nil)
      params = {}
      params[:market] = market if market.present?
      get("/v1/artists/#{URI.encode_www_form_component(id)}/top-tracks", params)
    end

    def playlists(limit: 50)
      get("/v1/me/playlists", limit: limit.clamp(1, 50))
    end

    def playlist_tracks(id, limit: 100)
      get("/v1/playlists/#{URI.encode_www_form_component(id)}/items", limit: limit.clamp(1, 100))
    end

    private

    attr_reader :account

    # One request per id, deliberately. Spotify's batch forms of these two
    # endpoints (/v1/tracks?ids=, /v1/artists?ids=) answer 403 for this app
    # while the single-resource forms are fine, so the obvious `?ids=` call is
    # not available to us. Callers only ever ask about rows they have yet to
    # fill in, which is what keeps an interrupted run cheap to resume.
    #
    # A rate limit is left to propagate for that reason; a resource that has
    # simply gone away is skipped.
    def fetch_each(path, ids)
      Array(ids).compact_blank.uniq.filter_map do |id|
        get("#{path}/#{id}")
      rescue NotFoundError
        nil
      end
    end

    def get(path, params = {})
      uri = URI.join(API_HOST, path)
      uri.query = URI.encode_www_form(params) if params.any?

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{account.fresh_access_token}"
      request["Accept"] = "application/json"

      handle(perform(uri, request))
    end

    def perform(uri, request)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                          open_timeout: OPEN_TIMEOUT,
                                          read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end
    end

    def handle(response)
      status = response.code.to_i

      case status
      when 200 then JSON.parse(response.body.presence || "{}")
      when 204 then nil
      when 401
        raise AuthError.new("Spotify rejected the access token", status:, body: response.body)
      when 404
        raise NotFoundError.new("Spotify has no such resource", status:, body: response.body)
      when 429
        raise RateLimitedError.new("Rate limited by Spotify",
                                   retry_after: response["Retry-After"].to_i,
                                   status:, body: response.body)
      else
        raise Error.new("Spotify API returned #{status}", status:, body: response.body)
      end
    end
  end
end
