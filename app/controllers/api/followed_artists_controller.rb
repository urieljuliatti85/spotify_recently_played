module Api
  class FollowedArtistsController < BaseController
    # Who the owner follows on Spotify — not derived from anything synced
    # locally. This route is public and cached: a burst of visitors would
    # still spend the owner's Spotify quota fetching their own follow list.
    def index
      payload = Rails.cache.fetch("spotify:followed_artists", expires_in: 1.hour) do
        Spotify::Client.new.followed_artists
      end

      artists = Array(payload.dig("artists", "items")).filter_map { |artist| serialize(artist) }
      render json: { artists: artists }
    rescue Spotify::Error => e
      raise unless e.status == 403

      render json: {
        error: "Spotify follow permission is missing. Reconnect Spotify to grant user-follow-read."
      }, status: :forbidden
    end

    private

    def serialize(artist)
      return if artist["id"].blank? || artist["name"].blank?

      {
        id: artist["id"],
        name: artist["name"],
        image_url: Spotify::ImagePicker.call(artist["images"]),
        spotify_url: artist.dig("external_urls", "spotify"),
        followers: artist.dig("followers", "total")
      }
    end
  end
end
