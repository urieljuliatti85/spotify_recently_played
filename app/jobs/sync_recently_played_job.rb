class SyncRecentlyPlayedJob < ApplicationJob
  queue_as :default

  # A missed poll just means the next one picks the plays up.
  discard_on Spotify::NotConnectedError

  retry_on Spotify::RateLimitedError, wait: :polynomially_longer, attempts: 5
  retry_on Spotify::Error, wait: 30.seconds, attempts: 3

  def perform
    result = Spotify::RecentlyPlayedSync.call
    Rails.logger.info("[spotify] imported #{result.imported} play(s)")
    result
  end
end
