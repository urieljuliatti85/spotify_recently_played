module Api
  # Lets the frontend distinguish "nothing played yet" from "not linked yet",
  # and tells it who is on the feed.
  class StatusController < BaseController
    def show
      listeners = SpotifyAccount.listed.to_a
      # One grouped count for everyone rather than one query per listener.
      counts = Play.where(spotify_account_id: listeners.map(&:id)).group(:spotify_account_id).count

      render json: {
        configured: Spotify.configured?,
        connected: SpotifyAccount.any_connected?,
        listeners: listeners.map { |listener| serialize(listener, counts) }
      }
    end

    private

    def serialize(listener, counts)
      {
        id: listener.id,
        name: listener.display_name,
        spotify_url: listener.spotify_user_id.present? ? "https://open.spotify.com/user/#{listener.spotify_user_id}" : nil,
        avatar_url: listener.avatar_url,
        owner: listener.owner,
        last_synced_at: listener.last_synced_at&.iso8601,
        plays_count: counts.fetch(listener.id, 0)
      }
    end
  end
end
