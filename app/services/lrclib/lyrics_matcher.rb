module Lrclib
  # Looks up the lyrics for a track — lrclib and Spotify share no identifier,
  # so title/artist/album/duration is all there is to go on. Callers are
  # expected to cache the result (see Lyric).
  class LyricsMatcher
    def self.call(...) = new(...).call

    def initialize(track, client: Client.new)
      @track = track
      @client = client
    end

    # The raw lrclib payload (a hash with "plainLyrics"/"syncedLyrics"/
    # "instrumental"), or nil when nothing looked like a match. Never raises:
    # a lookup failure reads the same as "no lyrics found" to Lyric#store!.
    def call
      exact_match || best_from_search
    rescue Error => e
      Rails.logger.warn("[Lrclib] lookup failed for #{track.spotify_id}: #{e.message}")
      nil
    end

    private

    attr_reader :track, :client

    def exact_match
      client.get(track_name: track.name, artist_name: primary_artist,
                  album_name: track.album_name, duration: duration_seconds)
    end

    # The search endpoint has no album/duration filter, so it turns up covers
    # and live versions alongside the studio track — the first result with
    # actual lyrics is the best bet without re-implementing lrclib's own
    # ranking.
    def best_from_search
      results = client.search(track_name: track.name, artist_name: primary_artist)
      results.find { |r| r["instrumental"] || r["plainLyrics"].present? }
    end

    # lrclib expects one artist; "artist_names" is Spotify's full credit
    # line ("A, B, C"), and the first credit is the one lrclib is most
    # likely to have tagged the track under.
    def primary_artist
      track.artist_names.to_s.split(",").first.to_s.strip
    end

    def duration_seconds
      return nil if track.duration_ms.blank?

      track.duration_ms / 1000
    end
  end
end
