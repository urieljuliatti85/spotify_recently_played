module Spotify
  # The tracks this feed has never played, drawn from the artists it already
  # listens to.
  #
  # The obvious source for this is /v1/artists/{id}/top-tracks, and it is not
  # available: that endpoint answers 403 for this app, the same way the batch
  # `?ids=` forms do (see Spotify::Client#fetch_each). A catalogue search
  # filtered to the artist is the closest thing that does answer — Spotify
  # ranks those by popularity too — and it costs the same one request per
  # artist.
  #
  # That request is against the owner's token, so this deliberately is not "all
  # the artists on the feed": it walks the most played ones first and stops at
  # MAX_ARTISTS. Each answer is cached for an hour, so a second look costs
  # nothing.
  class UnheardTracks
    MAX_ARTISTS = 15
    # Search refuses any limit above 10 for this app, the same restriction that
    # rules out the batch endpoints.
    PER_ARTIST = 10

    def self.call(...) = new(...).call

    def initialize(client: Client.new, market: Spotify.market, artists: MAX_ARTISTS)
      @client = client
      @market = market
      @artists = artists.to_i.clamp(1, MAX_ARTISTS)
    end

    def call
      # One query, not one per candidate: a track counts as heard exactly when
      # this database has a row for it, since Track rows only ever come from
      # plays.
      heard = Track.pluck(:spotify_id).to_set
      seen = Set.new

      top_artists.flat_map do |artist|
        found(artist).filter_map do |track|
          next if track["id"].blank? || track["name"].blank?
          next if heard.include?(track["id"]) || !seen.add?(track["id"])

          serialize(track, artist)
        end
      end
    end

    private

    attr_reader :client, :market, :artists

    # Most played first, so that when the ceiling cuts the list off it cuts off
    # the artists this feed cares least about.
    def top_artists
      Artist.joins(tracks: :plays)
        .group("artists.id")
        .order(Arel.sql("COUNT(plays.id) DESC"), :name)
        .limit(artists)
    end

    # One artist Spotify has since renamed or dropped must not empty the whole
    # suggestion list, so each is allowed to fail alone — the same reason the
    # sync runs one job per listener rather than one for everyone. A rate limit
    # or a dead token is different: those mean the next fourteen requests would
    # fail the same way, so they stop the walk instead of being logged fifteen
    # times.
    def found(artist)
      payload = Rails.cache.fetch("spotify:artist_catalogue:#{artist.spotify_id}", expires_in: 1.hour) do
        client.search(%(artist:"#{artist.name}"), type: "track", limit: PER_ARTIST, market: market)
      end

      # The search filter matches on the artist's *name*, so a band that shares
      # one with somebody else comes back mixed in. The credited id is what
      # settles it.
      Array(payload.dig("tracks", "items")).select do |track|
        Array(track["artists"]).any? { |credit| credit["id"] == artist.spotify_id }
      end
    rescue RateLimitedError, AuthError, NotConnectedError
      raise
    rescue Error => e
      Rails.logger.warn("[UnheardTracks] #{artist.name} (#{artist.spotify_id}): #{e.message}")
      []
    end

    def serialize(track, artist)
      {
        spotify_id: track["id"],
        name: track["name"],
        artists: Array(track["artists"]).map { |credit| credit["name"] }.join(", "),
        album: track.dig("album", "name"),
        album_image_url: Track.pick_image(track.dig("album", "images")),
        spotify_url: track.dig("external_urls", "spotify"),
        duration_ms: track["duration_ms"],
        explicit: track["explicit"] || false,
        # Which artist on the feed suggested it: the review list groups by this,
        # and a track credited to a guest would otherwise look like it came out
        # of nowhere.
        from: { id: artist.spotify_id, name: artist.name }
      }
    end
  end
end
