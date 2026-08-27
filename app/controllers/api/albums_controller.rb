module Api
  class AlbumsController < BaseController
    EDITION_SUFFIX = /\s*[-\u2013\u2014]\s*(?:\d{4}\s+)?(?:re-?master|remastered|reissue|deluxe|expanded|anniversary|mono|stereo|bonus|version|edition)\b.*\z/

    def releases
      title = params[:title].to_s.strip
      artist = params[:artist].to_s.strip
      return render json: { releases: [] } if title.blank? || artist.blank?

      releases = Rails.cache.fetch("discogs:album_releases:#{title}:#{artist}", expires_in: 2.minutes) do
        shelf.album_releases(title, artist)
          .select { |release| same_release?(release, title, artist) }
          .uniq { |release| release["discogs_id"] }
      end

      render json: { releases: releases }
    rescue DiscogsShelf::Error => e
      render json: { error: e.message }, status: :bad_gateway
    end

    def discogs
      match = DiscogsMatch.where(spotify_album_id: params[:id]).order(matched_at: :desc).first
      return render json: { url: nil } unless match

      render json: { url: "https://www.discogs.com/release/#{match.discogs_id}" }
    end

    def tracks
      payload = Rails.cache.fetch("spotify:album_tracks:#{params[:id]}", expires_in: 1.hour) do
        Spotify::Client.new.album(params[:id], market: Spotify.setting(:market))
      end

      render json: { tracks: Array(payload["tracks"]).filter_map { |track| serialize(track) } }
    rescue Spotify::NotConnectedError => e
      render json: { error: e.message }, status: :service_unavailable
    rescue Spotify::NotFoundError
      render json: { error: "Album not found on Spotify" }, status: :not_found
    rescue Spotify::Error => e
      render json: { error: e.message }, status: :bad_gateway
    end

    private

    def shelf
      @shelf ||= DiscogsShelf::Client.new
    end

    def same_release?(release, title, artist)
      same_title?(release["title"], title) &&
        same_artist?(release["artist"] || Array(release["artists"]).first, artist)
    end

    # Neither side spells the album the way the other one does: Spotify hangs
    # editions off the title ("Hexed (Deluxe Version)", "Feel the Darkness
    # (2018 Reissue)") and Discogs hangs subtitles off it ("Unleashed In The
    # East (Live In Japan)"). Comparing the bare titles alone misses the record
    # sitting right there on the shelf, so compare the stripped-down cores too.
    def same_title?(release_title, title)
      normalize(release_title) == normalize(title) ||
        core_title(release_title) == core_title(title)
    end

    def same_artist?(release_artist, requested_artist)
      release_artist = normalize(release_artist)
      requested_artists = requested_artist.to_s.split(",").map { |name| normalize(name) }.reject(&:blank?)

      requested_artists.any? { |artist| artist == release_artist || artist.include?(release_artist) } ||
        release_artist.present? && requested_artists.any? { |artist| release_artist.include?(artist) }
    end

    def normalize(value)
      value.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.strip
    end

    # Parenthesised groups go entirely; a trailing dash only counts as an
    # edition marker when it names one, because plenty of records legitimately
    # carry a dash ("Three - Architects Of Troubled Sleep") and dropping that
    # half would collapse unrelated titles onto each other.
    def core_title(value)
      core = normalize(value)
        .gsub(/\([^)]*\)|\[[^\]]*\]/, " ")
        .sub(EDITION_SUFFIX, "")
        .squeeze(" ")
        .strip

      core.presence || normalize(value)
    end

    def serialize(track)
      return if track["id"].blank? || track["name"].blank?

      {
        spotify_id: track["id"],
        name: track["name"],
        artists: Array(track["artists"]).map { |artist| artist["name"] }.join(", "),
        album: track.dig("album", "name"),
        album_spotify_id: track.dig("album", "id"),
        album_image_url: Track.pick_image(track.dig("album", "images")),
        spotify_url: track.dig("external_urls", "spotify"),
        duration_ms: track["duration_ms"],
        explicit: track["explicit"] || false
      }
    end
  end
end
