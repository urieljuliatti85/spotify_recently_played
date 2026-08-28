module Api
  class PlaylistsController < BaseController
    def index
      payload = Rails.cache.fetch("spotify:playlists", expires_in: 5.minutes) do
        Spotify::Client.new.playlists
      end

      # Hoisted out of the loop: this used to be one SELECT per playlist.
      owner_id = SpotifyAccount.find_owner&.spotify_user_id

      render json: {
        playlists: Array(payload["items"]).filter_map do |playlist|
          next unless playlist["public"] && playlist.dig("owner", "id") == owner_id

          {
            id: playlist["id"],
            name: playlist["name"],
            description: playlist["description"],
            image_url: Spotify::ImagePicker.call(playlist["images"]),
            spotify_url: playlist.dig("external_urls", "spotify"),
            tracks_count: playlist.dig("items", "total") || playlist.dig("tracks", "total") || 0
          }
        end
      }
    rescue Spotify::Error => e
      raise unless e.status == 403

      render json: {
        error: "Spotify playlist permission is missing. Reconnect Spotify to grant playlist-read-private."
      }, status: :forbidden
    end

    def tracks
      payload = Spotify::Client.new.playlist(params[:id], market: Spotify.market)
      # Despite what the reference docs call it, Spotify answers with this
      # nested under "items", not "tracks" — same ambiguity #index already
      # guards against for tracks_count.
      track_page = payload["items"] || payload["tracks"] || {}

      render json: {
        playlist: {
          id: payload["id"],
          name: payload["name"],
          description: payload["description"],
          image_url: Spotify::ImagePicker.call(payload["images"]),
          spotify_url: payload.dig("external_urls", "spotify")
        },
        tracks: Array(track_page["items"]).filter_map do |entry|
          Spotify::TrackSerializer.call(entry["item"] || entry["track"])
        end
      }
    rescue Spotify::NotFoundError
      render json: { error: "Playlist not found on Spotify" }, status: :not_found
    end
  end
end
