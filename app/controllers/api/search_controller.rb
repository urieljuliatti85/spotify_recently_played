module Api
  # Spotify's catalogue, not this feed's history. The search box's other job —
  # narrowing the plays already in memory — is client-side (lib/derive.js's
  # `matching`) and free; this one spends the owner's Spotify quota the same
  # way Api::AlbumsController#tracks does, so results are cached briefly to
  # keep a popular query from being paid for on every keystroke that reaches it.
  class SearchController < BaseController
    MAX_RESULTS = 8

    def index
      query = params[:q].to_s.strip
      return render json: { tracks: [], albums: [] } if query.blank?

      payload = Rails.cache.fetch("spotify:catalog_search:#{query.downcase}", expires_in: 1.minute) do
        Spotify::Client.new.search(query, type: "track,album", limit: MAX_RESULTS, market: Spotify.market)
      end

      render json: {
        tracks: Array(payload.dig("tracks", "items")).filter_map { |track| serialize_track(track) },
        albums: Array(payload.dig("albums", "items")).filter_map { |album| serialize_album(album) }
      }
    end

    private

    def serialize_track(track)
      Spotify::TrackSerializer.call(track, include_album_id: true, artist_list: true)
    end

    def serialize_album(album)
      return if album.blank? || album["id"].blank? || album["name"].blank?

      {
        spotify_id: album["id"],
        name: album["name"],
        artists: Array(album["artists"]).map { |artist| artist["name"] }.join(", "),
        image_url: Spotify::ImagePicker.call(album["images"]),
        spotify_url: album.dig("external_urls", "spotify")
      }
    end
  end
end
