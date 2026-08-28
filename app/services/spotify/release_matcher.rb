module Spotify
  # Works out which Spotify album a Discogs release is, and which of its tracks
  # can actually be played.
  #
  # Discogs and Spotify do not share an identifier, so the only bridge is the
  # text: artist, title, and the tracklist. That is guesswork, and it is priced
  # accordingly — one album search plus one album fetch per release, with a
  # capped per-track fallback for the leftovers. Callers are expected to cache
  # the result (see the DiscogsMatch model); nothing here is cheap enough to
  # run on a list endpoint.
  class ReleaseMatcher
    # A Discogs tracklist row that is a heading or an index entry is not a
    # track; only these types (and a blank one) name something playable.
    TRACK_TYPES = [ nil, "", "track" ].freeze

    ALBUM_CANDIDATES = 8
    # How close a candidate album's title has to be before it is considered at
    # all. Low enough for "…​(Live In Japan)" vs "…", high enough that a
    # different record by the same artist loses.
    ALBUM_TITLE_FLOOR = 0.55
    ALBUM_SCORE_FLOOR = 0.5
    TRACK_TITLE_FLOOR = 0.7
    # Falling back to one search per unmatched track is what makes a
    # compilation work at all, and also what could turn one release into fifty
    # requests. This is the ceiling.
    MAX_TRACK_SEARCHES = 12

    # Words that describe a pressing rather than the recording. Dropping them is
    # what lets Discogs' "Exciter" meet Spotify's "Exciter - Live", and a
    # Discogs pressing meet the Spotify remaster. Words that change which
    # recording it is — remix, acoustic, instrumental, demo — are deliberately
    # not here.
    NOISE = %w[
      remaster remastered remasterizado deluxe edition expanded reissue
      version anniversary bonus disc original mono stereo lp ep album
      live single radio edit take
      the a an
    ].to_set.freeze

    def self.call(...) = new(...).call

    def initialize(release, client: Client.new, market: Spotify.market)
      @release = release.to_h
      @client = client
      @market = market
      @searches = 0
    end

    def call
      album = find_album
      album_tracks = album ? tracks_of(album) : []
      tracks = match_tracks(album_tracks)

      {
        "album" => album && serialize_album(album),
        "tracks" => tracks,
        "track_count" => tracks.size,
        # Matched is not the same as playable: with a market in hand Spotify
        # will name a track it will not stream here, and a badge that counted
        # those would promise something the player cannot deliver.
        "playable_count" => tracks.count { |track| track.dig("track", "playable") },
        "market" => market
      }
    end

    private

    attr_reader :release, :client, :market

    def title = release["title"].to_s
    def artist = release["artist"].to_s
    def year = release["year"].to_i

    # "Various" is Discogs' compilation artist. Searching for it as if it were
    # a band matches nothing, so the artist filter is dropped for those.
    def compilation?
      artist.blank? || artist.match?(/\Avarious\b/i)
    end

    def discogs_tracks
      Array(release["tracklist"]).select do |track|
        TRACK_TYPES.include?(track["type"]) && track["title"].present?
      end
    end

    # --- album ---------------------------------------------------------------

    def find_album
      queries.each do |query|
        best = best_album(search_albums(query))
        return best if best
      end

      nil
    end

    # The field-filtered query is the precise one; the loose one is what saves a
    # release whose punctuation or credit line does not survive the filters.
    def queries
      return [ title ] if compilation?

      [ %(album:"#{title}" artist:"#{artist}"), "#{artist} #{title}" ]
    end

    def search_albums(query)
      payload = client.search(query, type: "album", limit: ALBUM_CANDIDATES, market: market)
      Array(payload&.dig("albums", "items"))
    rescue NotFoundError
      []
    end

    def best_album(candidates)
      scored = candidates.filter_map do |candidate|
        score = album_score(candidate)
        [ candidate, score ] if score >= ALBUM_SCORE_FLOOR
      end

      best = scored.max_by(&:last) or return nil
      album, score = best
      album.merge("confidence" => score.round(2))
    end

    def album_score(candidate)
      title_score = self.class.similarity(candidate["name"], title)
      return 0.0 if title_score < ALBUM_TITLE_FLOOR

      artist_score = compilation? ? 0.5 : self.class.similarity(names_of(candidate["artists"]), artist)

      title_score * 0.6 + artist_score * 0.3 + year_score(candidate) * 0.1
    end

    # Pressings drift by a year or two from the original release, and Discogs
    # dates the pressing while Spotify dates the reissue. Close counts.
    def year_score(candidate)
      return 0.5 if year.zero?

      candidate_year = candidate["release_date"].to_s[0, 4].to_i
      return 0.5 if candidate_year.zero?

      distance = (candidate_year - year).abs
      return 1.0 if distance <= 1
      distance <= 5 ? 0.6 : 0.2
    end

    def tracks_of(album)
      # The search payload carries no tracklist; the album endpoint does, along
      # with `is_playable` once a market is in play.
      detail = client.album(album["id"], market: market)
      Array(detail&.dig("tracks", "items")).map { |track| track.merge("album" => album) }
    rescue NotFoundError
      []
    end

    # --- tracks --------------------------------------------------------------

    def match_tracks(album_tracks)
      pool = album_tracks.dup

      discogs_tracks.map do |track|
        found = take_best(pool, track["title"])
        source = found ? "album" : "search"
        found ||= search_track(track["title"])

        {
          "position" => track["position"],
          "title" => track["title"],
          "duration" => track["duration"].presence,
          "artists" => Array(track["artists"]).join(", ").presence,
          "track" => found && serialize_track(found),
          "source" => found ? source : nil
        }
      end
    end

    # Destructive on purpose: an album that lists the same title twice must not
    # hand the same Spotify track to both rows.
    def take_best(pool, wanted)
      best, score = pool.map { |candidate| [ candidate, self.class.similarity(candidate["name"], wanted) ] }
                        .max_by(&:last)
      return nil if best.nil? || score < TRACK_TITLE_FLOOR

      pool.delete(best)
      best
    end

    def search_track(wanted)
      return nil if @searches >= MAX_TRACK_SEARCHES

      @searches += 1
      query = compilation? ? %(track:"#{wanted}") : %(track:"#{wanted}" artist:"#{artist}")
      payload = client.search(query, type: "track", limit: 5, market: market)

      Array(payload&.dig("tracks", "items")).find do |candidate|
        self.class.similarity(candidate["name"], wanted) >= TRACK_TITLE_FLOOR
      end
    rescue NotFoundError
      nil
    end

    # --- serialization -------------------------------------------------------

    def serialize_album(album)
      {
        "spotify_id" => album["id"],
        "name" => album["name"],
        "artists" => names_of(album["artists"]),
        "image_url" => Spotify::ImagePicker.call(album["images"]),
        "spotify_url" => album.dig("external_urls", "spotify"),
        "release_date" => album["release_date"],
        "total_tracks" => album["total_tracks"],
        "confidence" => album["confidence"]
      }
    end

    # The shape PlayerBar plays, same as the playlists endpoint serves.
    # `is_playable` is only present when a market was sent; its absence means
    # "unknown", which is not the same as false.
    def serialize_track(track)
      album = track["album"] || {}

      {
        "spotify_id" => track["id"],
        "name" => track["name"],
        "artists" => names_of(track["artists"]).presence || names_of(album["artists"]),
        "album" => album["name"],
        "album_image_url" => Spotify::ImagePicker.call(album["images"]),
        "spotify_url" => track.dig("external_urls", "spotify"),
        "duration_ms" => track["duration_ms"],
        "explicit" => track["explicit"] || false,
        "playable" => track["is_playable"] != false
      }
    end

    def names_of(artists)
      Array(artists).filter_map { |a| a["name"] }.join(", ")
    end

    # --- text ----------------------------------------------------------------

    class << self
      # Discogs separates a title from its translated variant with " = " —
      # Brazilian pressings are full of "Exciter (Excitador)" and
      # 'The Green Manalishi … = O "Manalishi" Verde …'. Only the first half
      # is the title Spotify knows. Bracketed asides ("(Live In Japan)",
      # "[2011 Remaster]") describe the pressing, and the two catalogues never
      # word them the same way.
      def normalize(text)
        text.to_s
            .split(/\s=\s/).first.to_s
            .unicode_normalize(:nfd)
            .gsub(/\p{Mn}/, "")
            .downcase
            .gsub(/\([^)]*\)|\[[^\]]*\]/, " ")
            .gsub(/[^a-z0-9]+/, " ")
            .strip
      end

      def tokens(text)
        normalize(text).split.reject { |token| NOISE.include?(token) }
      end

      # 1.0 for the same string, otherwise how much of the two token sets
      # overlap. Word-level rather than character-level: the differences that
      # matter here are whole words ("Live", "Pt. 2"), and an edit distance
      # would call "Rain" and "Ruin" nearly identical.
      def similarity(left, right)
        return 0.0 if left.blank? || right.blank?
        return 1.0 if normalize(left) == normalize(right)

        a = tokens(left).to_set
        b = tokens(right).to_set
        return 0.0 if a.empty? || b.empty?

        (a & b).size.to_f / (a | b).size
      end
    end
  end
end
