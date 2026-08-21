module Api
  class ArtistsController < BaseController
    # An artist's top tracks barely change from hour to hour, and this route is
    # public: without the cache every visitor costs one Spotify request against
    # the owner's quota. A failure raises out of `fetch`, so only real payloads
    # are ever stored.
    def tracks
      payload = Rails.cache.fetch("spotify:artist_top_tracks:#{params[:id]}", expires_in: 1.hour) do
        Spotify::Client.new.artist_top_tracks(params[:id])
      end

      render json: { tracks: Array(payload["tracks"]).filter_map { |track| serialize(track) } }
    rescue Spotify::NotConnectedError => e
      render json: { error: e.message }, status: :service_unavailable
    rescue Spotify::NotFoundError
      render json: { error: "Artist not found on Spotify" }, status: :not_found
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
        album_image_url: Track.pick_image(track.dig("album", "images")),
        spotify_url: track.dig("external_urls", "spotify"),
        duration_ms: track["duration_ms"],
        explicit: track["explicit"] || false,
        artist_list: Array(track["artists"]).filter_map do |artist|
          next if artist["id"].blank? || artist["name"].blank?

          {
            id: artist["id"],
            name: artist["name"],
            url: artist.dig("external_urls", "spotify")
          }
        end
      }
    end
  end
end
