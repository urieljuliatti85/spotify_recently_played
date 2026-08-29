# One Spotify track, resolved against YouTube's own catalogue.
#
# Matching a track costs a YouTube Data API search — 100 quota units against a
# 10,000/day default, i.e. about 100 searches a day — and never changes
# between visitors, so it is worked out once and kept. A track nobody has
# asked about yet simply has no row, and reads as unresolved rather than
# "no clip". Mirrors DiscogsMatch.
class YoutubeMatch < ApplicationRecord
  # Long enough that browsing the feed costs nothing on a return visit, short
  # enough that a clip uploaded after the first ask stops reading as missing.
  FRESH_FOR = 30.days

  validates :spotify_track_id, presence: true, uniqueness: true

  scope :for_ids, ->(ids) { where(spotify_track_id: Array(ids)) }

  # The cached match for a track, computed on first ask and after it goes
  # stale.
  def self.resolve(track)
    match = find_or_initialize_by(spotify_track_id: track.spotify_id)
    return match if match.persisted? && match.fresh?

    match.store!(Youtube::ClipMatcher.call(track))
    match
  rescue ActiveRecord::RecordNotUnique
    # Two visitors asked about the same track at once. The other request
    # already wrote a row; theirs is as good as this one.
    find_by!(spotify_track_id: track.spotify_id)
  end

  def fresh?
    matched_at.present? && matched_at > FRESH_FOR.ago
  end

  def store!(found_video_id)
    update!(video_id: found_video_id, matched_at: Time.current)
    self
  end

  def video_url
    "https://www.youtube.com/watch?v=#{video_id}" if video_id.present?
  end
end
