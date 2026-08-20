class Artist < ApplicationRecord
  has_many :track_artists, dependent: :destroy
  has_many :tracks, through: :track_artists

  validates :spotify_id, presence: true, uniqueness: true
  validates :name, presence: true

  # Builds/updates the local copy of an artist from Spotify's API payload.
  # The objects nested inside a track are "simplified" — no images — so the
  # image only fills in when a fuller payload comes along.
  def self.upsert_from_spotify!(payload)
    artist = find_or_initialize_by(spotify_id: payload["id"])

    artist.name = payload["name"].presence || artist.name
    artist.spotify_url = payload.dig("external_urls", "spotify").presence || artist.spotify_url
    image = Track.pick_image(payload["images"])
    artist.image_url = image if image.present?

    artist.save! if artist.changed?
    artist
  end
end
