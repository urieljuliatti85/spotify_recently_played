# One Spotify track, resolved against lrclib.net's public lyrics catalogue.
#
# lrclib is free and unauthenticated — unlike YoutubeMatch there is no daily
# quota to protect — but the lookup is still two HTTP round trips in the
# worst case (an exact match, then a text search fallback), and the result
# never changes, so it is still worth keeping. Mirrors YoutubeMatch.
class Lyric < ApplicationRecord
  FRESH_FOR = 30.days

  validates :spotify_track_id, presence: true, uniqueness: true

  # The cached lookup for a track, computed on first ask and after it goes
  # stale.
  def self.resolve(track)
    lyric = find_or_initialize_by(spotify_track_id: track.spotify_id)
    return lyric if lyric.persisted? && lyric.fresh?

    lyric.store!(Lrclib::LyricsMatcher.call(track))
    lyric
  rescue ActiveRecord::RecordNotUnique
    # Two visitors asked about the same track at once. The other request
    # already wrote a row; theirs is as good as this one.
    find_by!(spotify_track_id: track.spotify_id)
  end

  def fresh?
    matched_at.present? && matched_at > FRESH_FOR.ago
  end

  def store!(result)
    result ||= {}
    update!(
      plain_lyrics: result["plainLyrics"],
      synced_lyrics: result["syncedLyrics"],
      instrumental: result["instrumental"] || false,
      matched_at: Time.current
    )
    self
  end

  # An instrumental track has no lyrics to show and that is itself the
  # answer — distinct from a lookup that simply came back empty.
  def found?
    instrumental? || plain_lyrics.present?
  end

  def summary
    {
      found: found?,
      instrumental: instrumental,
      plain_lyrics: plain_lyrics,
      synced_lyrics: synced_lyrics
    }
  end
end
