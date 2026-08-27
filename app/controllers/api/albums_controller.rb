module Api
  class AlbumsController < BaseController
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
