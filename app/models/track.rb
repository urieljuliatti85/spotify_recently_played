class Track < ApplicationRecord
  has_many :plays, dependent: :destroy

  validates :spotify_id, presence: true, uniqueness: true
  validates :name, presence: true

  # Builds/updates the local copy of a track from Spotify's API payload.
  def self.upsert_from_spotify!(payload)
    track = find_or_initialize_by(spotify_id: payload["id"])
    track.assign_attributes(
      name: payload["name"],
      artist_names: Array(payload["artists"]).map { |a| a["name"] }.join(", "),
      album_name: payload.dig("album", "name"),
      album_image_url: pick_album_image(payload.dig("album", "images")),
      spotify_url: payload.dig("external_urls", "spotify"),
      duration_ms: payload["duration_ms"],
      explicit: payload["explicit"] || false
    )
    track.save!
    track
  end

  # Spotify returns images widest-first; the middle one (~300px) is the best
  # fit for the cover art in the list without wasting bandwidth.
  def self.pick_album_image(images)
    images = Array(images)
    return nil if images.empty?

    (images.find { |i| i["width"].to_i.between?(200, 400) } || images.last)["url"]
  end
end
