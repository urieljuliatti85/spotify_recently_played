# The scheduled entry point: fans one sync job out per linked listener.
class SyncAllAccountsJob < ApplicationJob
  queue_as :default

  def perform
    SpotifyAccount.connected.find_each do |account|
      SyncRecentlyPlayedJob.perform_later(account)
    end
  end
end
