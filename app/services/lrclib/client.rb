require "net/http"

module Lrclib
  # Thin wrapper around lrclib.net's public, unauthenticated lyrics API.
  # lrclib asks integrations to send a descriptive User-Agent rather than
  # requiring a key — there is no quota to spend here, unlike Youtube::Client.
  class Client
    API_HOST = "https://lrclib.net".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10
    USER_AGENT = "spotify_recently_played (https://github.com/urieljuliatti/spotify_recently_played)".freeze

    # The exact-match endpoint wants the artist, title, album and duration to
    # all agree with lrclib's own copy of the tags — nil when nothing matched
    # that closely, not an error.
    def get(track_name:, artist_name:, album_name:, duration:)
      request("/api/get", track_name: track_name, artist_name: artist_name,
                           album_name: album_name, duration: duration)
    rescue NotFound
      nil
    end

    # The looser fallback: a text search, ranked by lrclib itself. Always an
    # array, empty when nothing came back.
    def search(track_name:, artist_name:)
      Array(request("/api/search", track_name: track_name, artist_name: artist_name))
    end

    private

    def request(path, params)
      uri = URI.join(API_HOST, path)
      uri.query = URI.encode_www_form(params.compact)

      req = Net::HTTP::Get.new(uri)
      req["User-Agent"] = USER_AGENT

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                                       open_timeout: OPEN_TIMEOUT,
                                                       read_timeout: READ_TIMEOUT) { |http| http.request(req) }
      handle(response, uri)
    rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
      raise Error, "lrclib did not answer (#{e.class})"
    end

    def handle(response, uri)
      raise NotFound if response.code.to_i == 404
      return JSON.parse(response.body.presence || "{}") if response.is_a?(Net::HTTPSuccess)

      raise Error, "lrclib returned #{response.code} for #{uri.path}"
    end
  end
end
