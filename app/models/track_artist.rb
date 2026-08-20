class TrackArtist < ApplicationRecord
  belongs_to :track
  belongs_to :artist

  validates :artist_id, uniqueness: { scope: :track_id }
end
