class Track < ApplicationRecord
  has_many :plays, dependent: :destroy
  # Credit order lives on the join rows. Reading it through `track_artists`
  # keeps it correct under `includes`, where a preloaded `artists` is fetched
  # on its own and has no join table to order by.
  has_many :track_artists, -> { order(:position) }, dependent: :destroy, inverse_of: :track
  has_many :artists, through: :track_artists

  validates :spotify_id, presence: true, uniqueness: true
  validates :name, presence: true

  # Builds/updates the local copy of a track from Spotify's API payload.
  def self.upsert_from_spotify!(payload)
    track = find_or_initialize_by(spotify_id: payload["id"])
    track.assign_attributes(
      name: payload["name"],
      artist_names: Array(payload["artists"]).map { |a| a["name"] }.join(", "),
      album_name: payload.dig("album", "name"),
      spotify_album_id: payload.dig("album", "id"),
      album_image_url: pick_image(payload.dig("album", "images")),
      spotify_url: payload.dig("external_urls", "spotify"),
      duration_ms: payload["duration_ms"],
      explicit: payload["explicit"] || false
    )
    track.save!
    track.sync_artists!(payload["artists"])
    track
  end

  # Spotify returns images widest-first; the middle one (~300px) is the best
  # fit for the cover art in the list without wasting bandwidth.
  def self.pick_image(images)
    images = Array(images)
    return nil if images.empty?

    (images.find { |i| i["width"].to_i.between?(200, 400) } || images.last)["url"]
  end

  # Links the track to one Artist row per credited artist, in Spotify's order.
  # `artist_names` stays alongside as the display string: it is what the feed
  # prints, and it survives even when an artist arrives without an id.
  def sync_artists!(payloads)
    linked = Array(payloads).each_with_index.filter_map do |payload, index|
      next if payload["id"].blank? || payload["name"].blank?

      artist = Artist.upsert_from_spotify!(payload)
      link = track_artists.find_or_initialize_by(artist_id: artist.id)
      link.position = index
      link.save! if link.changed?
      artist.id
    end

    # A re-credited track drops whoever is no longer on it. Guarded, because
    # `where.not(artist_id: [])` matches every row — a payload that arrives
    # without ids must leave the links it can't rebuild alone.
    track_artists.where.not(artist_id: linked).destroy_all if linked.any?
    track_artists.reset
    artists.reset
    linked
  end
end
