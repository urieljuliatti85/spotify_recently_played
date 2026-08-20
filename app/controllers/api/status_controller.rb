module Api
  # Lets the frontend distinguish "nothing played yet" from "not linked yet".
  class StatusController < BaseController
    def show
      account = SpotifyAccount.current

      render json: {
        configured: Spotify.configured?,
        connected: SpotifyAccount.connected?,
        display_name: account&.display_name,
        last_synced_at: account&.last_synced_at&.iso8601,
        plays_count: Play.count
      }
    end
  end
end
