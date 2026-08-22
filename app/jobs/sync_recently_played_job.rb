# Pulls one listener's recent plays. Per-account rather than all-in-one so a
# friend whose token has gone bad cannot stall everybody else's sync.
class SyncRecentlyPlayedJob < ApplicationJob
  queue_as :default

  # A missed poll just means the next one picks the plays up.
  discard_on Spotify::NotConnectedError
  # The account was unlinked between enqueue and run.
  discard_on ActiveJob::DeserializationError

  retry_on Spotify::RateLimitedError, wait: :polynomially_longer, attempts: 5
  retry_on Spotify::Error, wait: 30.seconds, attempts: 3

  def perform(account = nil)
    account ||= SpotifyAccount.owner
    raise Spotify::NotConnectedError, "No Spotify account linked yet" if account.nil?

    result = Spotify::RecentlyPlayedSync.call(account)
    Rails.logger.info("[spotify] #{account.display_name}: imported #{result.imported} play(s)")
    result
  end
end
