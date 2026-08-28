module Api
  class TopItemsController < BaseController
    # Six months of listening is enough to smooth out a single binge without
    # going so wide that it stops reflecting anything current.
    TIME_RANGE = "medium_term"
    RESULTS = 8

    # Spotify's own algorithmic picks for the owner — distinct from the
    # "Top Artists" shelf, which only ever reflects plays this app has synced.
    # This route is public and cached: it is the owner's own personalization
    # data, but a burst of visitors would still spend the owner's Spotify quota
    # fetching it on their behalf.
    def index
      payload = Rails.cache.fetch("spotify:top_items:#{TIME_RANGE}", expires_in: 6.hours) do
        client = Spotify::Client.new
        {
          "artists" => client.top_items(type: "artists", time_range: TIME_RANGE, limit: RESULTS),
          "tracks" => client.top_items(type: "tracks", time_range: TIME_RANGE, limit: RESULTS)
        }
      end

      render json: {
        artists: Array(payload.dig("artists", "items")).filter_map { |artist| serialize_artist(artist) },
        tracks: Array(payload.dig("tracks", "items")).filter_map { |track| Spotify::TrackSerializer.call(track) }
      }
    rescue Spotify::NotConnectedError => e
      render json: { error: e.message }, status: :service_unavailable
    rescue Spotify::Error => e
      if e.status == 403
        return render json: {
          error: "Spotify top items permission is missing. Reconnect Spotify to grant user-top-read."
        }, status: :forbidden
      end

      render json: { error: e.message }, status: :bad_gateway
    end

    private

    def serialize_artist(artist)
      return if artist["id"].blank? || artist["name"].blank?

      {
        id: artist["id"],
        name: artist["name"],
        image_url: Track.pick_image(artist["images"]),
        spotify_url: artist.dig("external_urls", "spotify")
      }
    end
  end
end
