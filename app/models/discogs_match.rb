# One Discogs release, resolved against the Spotify catalogue.
#
# Matching a release costs at least two Spotify requests and never changes
# between visitors, so it is worked out once and kept. The row is what lets the
# collection grid show "on Spotify" badges without spending a request per card:
# a release nobody has opened yet simply has no row, and reads as unknown.
class DiscogsMatch < ApplicationRecord
  # Long enough that browsing the shelf costs nothing, short enough that a
  # record which only reached Spotify later stops reading as missing.
  FRESH_FOR = 30.days

  validates :discogs_id, presence: true, uniqueness: true

  scope :for_ids, ->(ids) { where(discogs_id: Array(ids).map(&:to_i)) }

  # The cached match for a release, computed on first ask and after it goes
  # stale. `release` is the shelf's detail payload.
  def self.resolve(release, force: false)
    discogs_id = release["discogs_id"].to_i
    match = find_or_initialize_by(discogs_id: discogs_id)
    return match if match.persisted? && match.fresh? && !force

    match.store!(Spotify::ReleaseMatcher.call(release))
    match
  rescue ActiveRecord::RecordNotUnique
    # Two visitors opened the same record at once. The other request already
    # wrote a row; theirs is as good as this one.
    find_by!(discogs_id: discogs_id)
  end

  def fresh?
    payload.present? && matched_at.present? && matched_at > FRESH_FOR.ago
  end

  def store!(result)
    update!(
      payload: result,
      spotify_album_id: result.dig("album", "spotify_id"),
      track_count: result["track_count"].to_i,
      playable_count: result["playable_count"].to_i,
      matched_at: Time.current
    )
    self
  end

  # What the grid needs: enough to badge a card, not the whole tracklist.
  def summary
    {
      matched: spotify_album_id.present?,
      track_count: track_count,
      playable_count: playable_count,
      spotify_album_id: spotify_album_id,
      spotify_album_url: payload&.dig("album", "spotify_url"),
      matched_at: matched_at&.iso8601
    }
  end
end
