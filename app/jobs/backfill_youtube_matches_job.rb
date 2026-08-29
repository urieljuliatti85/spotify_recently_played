# Resolves a small, steady trickle of tracks against the YouTube Data API,
# independent of anyone visiting the feed.
#
# Api::TracksController only ever resolves a track a visitor's browser has
# actually asked about (capped per request), so a track nobody has scrolled
# to yet stays unresolved indefinitely — most of a real history, since
# browsing only ever surfaces what is on screen. This is what backfills the
# rest, at a pace (see BATCH_SIZE and config/recurring.yml's schedule) sized
# to stay well under the default 10,000-unit/100-search daily quota even
# alongside whatever visitors resolve in the foreground.
class BackfillYoutubeMatchesJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 1

  def perform
    return unless Youtube.configured?

    unresolved_tracks.each { |track| YoutubeMatch.resolve(track) }
  end

  private

  # Most-recently-played first: that is what a visitor is most likely to
  # actually be looking at, so it is worth more than backfilling deep history
  # nobody has scrolled to.
  def unresolved_tracks
    Track.where.not(spotify_id: fresh_matched_ids)
         .joins(:plays)
         .group(:id)
         .order(Arel.sql("MAX(plays.played_at) DESC"))
         .limit(BATCH_SIZE)
  end

  def fresh_matched_ids
    YoutubeMatch.where(matched_at: YoutubeMatch::FRESH_FOR.ago..).pluck(:spotify_track_id)
  end
end
