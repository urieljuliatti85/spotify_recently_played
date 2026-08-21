module Api
  class PlaylistsController < BaseController
    def index
      payload = Rails.cache.fetch("spotify:playlists", expires_in: 5.minutes) do
        Spotify::Client.new.playlists
      end

      render json: {
        playlists: Array(payload["items"]).filter_map do |playlist|
          next unless playlist["public"] && playlist.dig("owner", "id") == SpotifyAccount.current.spotify_user_id

          {
            id: playlist["id"],
            name: playlist["name"],
            description: playlist["description"],
            image_url: Track.pick_image(playlist["images"]),
            spotify_url: playlist.dig("external_urls", "spotify"),
            tracks_count: playlist.dig("items", "total") || playlist.dig("tracks", "total") || 0
          }
        end
      }
    rescue Spotify::NotConnectedError => e
      render json: { error: e.message }, status: :service_unavailable
    rescue Spotify::Error => e
      if e.status == 403
        return render json: {
          error: "Spotify playlist permission is missing. Reconnect Spotify to grant playlist-read-private."
        }, status: :forbidden
      end

      render json: { error: e.message }, status: :bad_gateway
    end

    def tracks
      payload = Spotify::Client.new.playlist_tracks(params[:id])

      render json: {
        tracks: Array(payload["items"]).filter_map do |entry|
          serialize_track(entry["item"] || entry["track"])
        end
      }
    rescue Spotify::NotConnectedError => e
      render json: { error: e.message }, status: :service_unavailable
    rescue Spotify::NotFoundError
      render json: { error: "Playlist not found on Spotify" }, status: :not_found
    rescue Spotify::Error => e
      render json: { error: e.message }, status: :bad_gateway
    end

    private

    def serialize_track(track)
      return if track.blank? || track["id"].blank? || track["name"].blank?

      {
        spotify_id: track["id"],
        name: track["name"],
        artists: Array(track["artists"]).map { |artist| artist["name"] }.join(", "),
        album: track.dig("album", "name"),
        album_image_url: Track.pick_image(track.dig("album", "images")),
        spotify_url: track.dig("external_urls", "spotify"),
        duration_ms: track["duration_ms"],
        explicit: track["explicit"] || false
      }
    end
  end
end
