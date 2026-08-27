require "net/http"

module DiscogsShelf
  # Read-only HTTP client for the sibling discogs_shelf app.
  #
  # Everything it exposes is already served from that app's local mirror of
  # Discogs, so these calls are cheap and do not spend anyone's Discogs quota —
  # except `release`, which the shelf backfills from Discogs on first open and
  # then caches for 30 days on its side.
  class Client
    OPEN_TIMEOUT = 3
    READ_TIMEOUT = 15
    LISTS = %w[collection wantlist].freeze

    def initialize(base_url = DiscogsShelf.base_url)
      raise NotConfiguredError, "DISCOGS_SHELF_URL is not set" if base_url.blank?

      @base_url = base_url.to_s.chomp("/")
    end

    # `list` is "collection" or "wantlist"; the shelf serves both off the same
    # query params (q, genre, style, media, decade, sort, page, per_page).
    def items(list, params = {})
      list = LISTS.include?(list.to_s) ? list.to_s : "collection"
      get("/api/#{list}", params)
    end

    def album_releases(title, artist)
      releases = LISTS.flat_map do |list|
        [ title, artist ].flat_map do |query|
          Array(items(list, q: query, per_page: 100)["items"])
        end
      end.uniq { |release| release["discogs_id"] }

      releases.map do |release|
        release.merge("marketplace" => marketplace(release["discogs_id"]))
      rescue Error => e
        Rails.logger.warn("[DiscogsShelf] marketplace lookup failed for #{release['discogs_id']}: #{e.message}")
        release
      end
    end

    def release(discogs_id)
      get("/api/releases/#{discogs_id.to_i}")
    end

    def marketplace(discogs_id)
      get("/api/releases/#{discogs_id.to_i}/marketplace")
    end

    def profile
      get("/api/profile")
    end

    private

    attr_reader :base_url

    def get(path, params = {})
      uri = URI.join(base_url + "/", path.delete_prefix("/"))
      uri.query = URI.encode_www_form(params.compact_blank) if params.present?

      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"

      handle(perform(uri, request), uri)
    rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
      raise UnreachableError, "Discogs Shelf at #{base_url} did not answer (#{e.class})"
    end

    def perform(uri, request)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                          open_timeout: OPEN_TIMEOUT,
                                          read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end
    end

    def handle(response, uri)
      status = response.code.to_i
      return JSON.parse(response.body.presence || "{}") if status == 200

      # The shelf answers JSON on its own errors ({ error:, message: }); its
      # message is the useful half, so pass it through instead of a bare code.
      message = begin
        JSON.parse(response.body.to_s)["message"]
      rescue JSON::ParserError
        nil
      end

      raise Error.new(message.presence || "Discogs Shelf returned #{status} for #{uri.path}", status: status)
    end
  end
end
