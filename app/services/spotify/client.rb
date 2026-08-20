require "net/http"

module Spotify
  # Thin wrapper around the Spotify Web API, scoped to the linked account.
  class Client
    API_HOST = "https://api.spotify.com".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    def initialize(account = SpotifyAccount.current)
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

    private

    attr_reader :account

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
