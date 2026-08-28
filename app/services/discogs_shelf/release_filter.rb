module DiscogsShelf
  # Filters a shelf listing down to the releases that are plausibly a given
  # Spotify album, by text — the two sides never spell an album the same way,
  # so this is fuzzy comparison, not exact matching. Bridges the same
  # Discogs↔Spotify gap Spotify::ReleaseMatcher does in the other direction
  # (a known Discogs release -> which Spotify tracks it is), just starting
  # from a known Spotify album instead.
  class ReleaseFilter
    # Neither side spells the album the way the other one does: Spotify hangs
    # editions off the title ("Hexed (Deluxe Version)", "Feel the Darkness
    # (2018 Reissue)") and Discogs hangs subtitles off it ("Unleashed In The
    # East (Live In Japan)"). Comparing the bare titles alone misses the
    # record sitting right there on the shelf, so the stripped-down core is
    # compared too.
    EDITION_SUFFIX = /\s*[-\u2013\u2014]\s*(?:\d{4}\s+)?(?:re-?master|remastered|reissue|deluxe|expanded|anniversary|mono|stereo|bonus|version|edition)\b.*\z/

    def self.call(releases, title:, artist:)
      Array(releases)
        .select { |release| same_release?(release, title, artist) }
        .uniq { |release| release["discogs_id"] }
    end

    def self.same_release?(release, title, artist)
      same_title?(release["title"], title) &&
        same_artist?(release["artist"] || Array(release["artists"]).first, artist)
    end

    def self.same_title?(release_title, title)
      normalize(release_title) == normalize(title) ||
        core_title(release_title) == core_title(title)
    end

    def self.same_artist?(release_artist, requested_artist)
      release_artist = normalize(release_artist)
      requested_artists = requested_artist.to_s.split(",").map { |name| normalize(name) }.reject(&:blank?)

      requested_artists.any? { |artist| artist == release_artist || artist.include?(release_artist) } ||
        release_artist.present? && requested_artists.any? { |artist| release_artist.include?(artist) }
    end

    def self.normalize(value)
      value.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.strip
    end

    # Parenthesised groups go entirely; a trailing dash only counts as an
    # edition marker when it names one, because plenty of records legitimately
    # carry a dash ("Three - Architects Of Troubled Sleep") and dropping that
    # half would collapse unrelated titles onto each other.
    def self.core_title(value)
      core = normalize(value)
        .gsub(/\([^)]*\)|\[[^\]]*\]/, " ")
        .sub(EDITION_SUFFIX, "")
        .squeeze(" ")
        .strip

      core.presence || normalize(value)
    end

    private_class_method :same_release?, :same_title?, :same_artist?, :normalize, :core_title
  end
end
