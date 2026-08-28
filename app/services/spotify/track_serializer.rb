module Spotify
  # Shared shape for a track as this app exposes it over the API. Album
  # tracks, artist top tracks, playlist tracks and personalized top items all
  # collapse to the same JSON — only where the album comes from differs: a
  # full track object carries its own nested "album", but the album tracks
  # endpoint returns bare tracks under a separate album payload.
  class TrackSerializer
    def self.call(track, album: nil, artist_list: false, include_album_id: false)
      return if track.blank? || track["id"].blank? || track["name"].blank?

      album ||= track["album"] || {}

      payload = {
        spotify_id: track["id"],
        name: track["name"],
        artists: Array(track["artists"]).map { |artist| artist["name"] }.join(", "),
        album: album["name"],
        album_image_url: Track.pick_image(album["images"]),
        spotify_url: track.dig("external_urls", "spotify"),
        duration_ms: track["duration_ms"],
        explicit: track["explicit"] || false
      }
      payload[:album_spotify_id] = album["id"] if include_album_id
      payload[:artist_list] = artist_list_for(track) if artist_list
      payload
    end

    def self.artist_list_for(track)
      Array(track["artists"]).filter_map do |artist|
        next if artist["id"].blank? || artist["name"].blank?

        { id: artist["id"], name: artist["name"], url: artist.dig("external_urls", "spotify") }
      end
    end
    private_class_method :artist_list_for
  end
end
