# Pulls one listener's recent plays. Per-account rather than all-in-one so a
# friend whose token has gone bad cannot stall everybody else's sync.
class SyncRecentlyPlayedJob < ApplicationJob
  queue_as :default

  retry_on Spotify::RateLimitedError, wait: :polynomially_longer, attempts: 5
  # Only Spotify::RateLimitedError and NotFoundError are worth a retry — a
  # missing account or a dead token will not fix itself by trying again.
  # ActiveJob resolves discard_on/retry_on the same way ActionController
  # resolves rescue_from: the *last* declared handler for a matching
  # exception wins, not the most specific one. Declaring the broad
  # `retry_on Spotify::Error` before the two discard_on calls below is what
  # keeps them from being shadowed by it — swap the order and every
  # NotConnectedError gets retried three times instead of discarded once.
  retry_on Spotify::Error, wait: 30.seconds, attempts: 3

  # A missed poll just means the next one picks the plays up.
  discard_on Spotify::NotConnectedError
  # The account was unlinked between enqueue and run.
  discard_on ActiveJob::DeserializationError

  def perform(account = nil)
    account ||= SpotifyAccount.find_owner
    raise Spotify::NotConnectedError, "No Spotify account linked yet" if account.nil?

    result = Spotify::RecentlyPlayedSync.call(account)
    Rails.logger.info("[spotify] #{account.display_name}: imported #{result.imported} play(s)")
    result
  end
end
