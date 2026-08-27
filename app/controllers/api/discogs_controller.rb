module Api
  # The Discogs tab. Records come from the sibling discogs_shelf app; what is
  # playable comes from Spotify.
  #
  # The split matters for cost: the list endpoint never touches Spotify and
  # only reports matches that some earlier visit already worked out, while the
  # detail endpoint is allowed to spend requests — once per release, then it is
  # cached in `discogs_matches` for everybody.
  class DiscogsController < BaseController
    LIST_CACHE = 2.minutes

    # What the record page prints. The shelf's detail payload also carries every
    # sleeve scan and every YouTube link Discogs has, which is a lot of bytes
    # for something nothing on this page reads.
    RELEASE_FIELDS = %w[
      discogs_id title artist artists year country label catno labels
      genres styles format_summary cover_url thumb_url discogs_url released notes
    ].freeze

    def status
      render json: {
        configured: DiscogsShelf.configured?,
        url: DiscogsShelf.base_url,
        spotify_connected: SpotifyAccount.any_connected?,
        **shelf_status
      }
    end

    def index
      payload = cached_items
      matches = DiscogsMatch.for_ids(Array(payload["items"]).map { |item| item["discogs_id"] })
                            .index_by(&:discogs_id)

      render json: {
        list: list_name,
        items: Array(payload["items"]).map { |item| item.merge("spotify" => matches[item["discogs_id"]]&.summary) },
        pagination: payload["pagination"],
        facets: payload["facets"],
        sort: payload["sort"]
      }
    rescue DiscogsShelf::Error => e
      render_shelf_error(e)
    end

    def show
      release = shelf.release(params[:id])
      match, error = resolve(release)
      spotify = match&.payload || {}
      marketplace = marketplace_for(params[:id])

      render json: {
        release: release.slice(*RELEASE_FIELDS),
        marketplace: marketplace,
        spotify: {
          album: spotify["album"],
          market: spotify["market"],
          track_count: spotify["track_count"] || 0,
          playable_count: spotify["playable_count"] || 0,
          matched_at: match&.matched_at&.iso8601,
          error: error
        },
        tracks: tracks_for(release, spotify)
      }
    rescue DiscogsShelf::Error => e
      render_shelf_error(e)
    end

    private

    def shelf
      @shelf ||= DiscogsShelf::Client.new
    end

    def list_name
      DiscogsShelf::Client::LISTS.include?(params[:list]) ? params[:list] : "collection"
    end

    def list_params
      params.permit(:q, :genre, :style, :media, :decade, :sort, :page, :per_page).to_h
    end

    # The shelf reads its own SQLite, so this is cheap — but the tab refetches
    # on every keystroke of its search box, and those repeat.
    def cached_items
      key = [ "discogs_shelf:items", list_name, list_params.sort.to_h ].join(":")

      Rails.cache.fetch(key, expires_in: LIST_CACHE) { shelf.items(list_name, list_params) }
    end

    # A release the site cannot match is still a release worth reading, so a
    # Spotify failure is reported alongside the tracklist rather than instead
    # of it.
    def resolve(release)
      [ DiscogsMatch.resolve(release), nil ]
    rescue Spotify::NotConnectedError
      [ nil, "No Spotify account is linked, so nothing can be matched yet." ]
    rescue Spotify::RateLimitedError
      [ nil, "Spotify is rate limiting this app. Try again in a minute." ]
    rescue Spotify::Error => e
      Rails.logger.warn("[Api::Discogs] match failed for #{release['discogs_id']}: #{e.message}")
      [ nil, "Spotify could not be reached, so playability is unknown." ]
    end

    # Every row of the Discogs tracklist, in Discogs' order, each carrying the
    # Spotify track it was matched to — or nothing, which is what "not on
    # Spotify" looks like.
    def tracks_for(release, spotify)
      matched = Array(spotify["tracks"]).index_by { |track| [ track["position"], track["title"] ] }

      Array(release["tracklist"]).map do |row|
        match = matched[[ row["position"], row["title"] ]] || {}
        track = match["track"]

        {
          position: row["position"],
          title: row["title"],
          duration: row["duration"],
          artists: Array(row["artists"]).join(", ").presence,
          type: row["type"],
          playable: track.present? && track["playable"] != false,
          source: match["source"],
          track: track
        }
      end
    end

    def marketplace_for(discogs_id)
      shelf.marketplace(discogs_id)
    rescue DiscogsShelf::Error => e
      Rails.logger.warn("[Api::Discogs] marketplace lookup failed for #{discogs_id}: #{e.message}")
      nil
    end

    def shelf_status
      profile = shelf.profile

      {
        reachable: true,
        username: profile["username"],
        collection_count: profile.dig("stats", "collection_count"),
        wantlist_count: profile.dig("stats", "wantlist_count"),
        last_sync: profile["last_sync"]
      }
    rescue DiscogsShelf::Error => e
      { reachable: false, error: e.message }
    end

    def render_shelf_error(error)
      status = case error
      when DiscogsShelf::NotConfiguredError, DiscogsShelf::UnreachableError then :service_unavailable
      else error.status == 404 ? :not_found : :bad_gateway
      end

      render json: { error: error.message, configured: DiscogsShelf.configured? }, status: status
    end
  end
end
