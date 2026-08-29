require "net/http"

module Youtube
  # Thin wrapper around the public YouTube Data API v3 search endpoint. Every
  # call spends quota (100 units against a 10,000/day default) regardless of
  # whether a video is found, so callers are expected to cache the result —
  # see YoutubeMatch — rather than search on every request.
  class Client
    API_HOST = "https://www.googleapis.com".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    # videoCategoryId 10 is YouTube's own "Music" category — narrowing to it
    # keeps a cover, a reaction video or a lyric-only upload from outranking
    # the actual clip.
    MUSIC_CATEGORY = "10"

    def search(query)
      payload = get("/youtube/v3/search",
        part: "snippet", type: "video", videoCategoryId: MUSIC_CATEGORY,
        maxResults: 1, q: query, key: Youtube.api_key)

      Array(payload["items"]).first
    end

    private

    def get(path, params)
      uri = URI.join(API_HOST, path)
      uri.query = URI.encode_www_form(params)

      request = Net::HTTP::Get.new(uri)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                                       open_timeout: OPEN_TIMEOUT,
                                                       read_timeout: READ_TIMEOUT) { |http| http.request(request) }

      handle(response, uri)
    rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
      raise Error, "YouTube did not answer (#{e.class})"
    end

    def handle(response, uri)
      return JSON.parse(response.body.presence || "{}") if response.is_a?(Net::HTTPSuccess)

      message = begin
        JSON.parse(response.body.to_s).dig("error", "message")
      rescue JSON::ParserError
        nil
      end

      raise Error, message.presence || "YouTube returned #{response.code} for #{uri.path}"
    end
  end
end
