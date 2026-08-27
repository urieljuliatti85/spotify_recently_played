module Api
  class AlbumsController < BaseController
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

    def same_release?(release, title, artist)
      normalize(release["title"]) == normalize(title) &&
        normalize(release["artist"] || Array(release["artists"]).first) == normalize(artist)
    end

    def normalize(value)
      value.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.strip
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
