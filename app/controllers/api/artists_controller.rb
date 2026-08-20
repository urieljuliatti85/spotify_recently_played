module Api
  class ArtistsController < BaseController
    def tracks
      payload = Spotify::Client.new.artist_top_tracks(params[:id])

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
