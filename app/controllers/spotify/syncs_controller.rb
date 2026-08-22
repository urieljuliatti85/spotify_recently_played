module Spotify
  # Owner-only: pull recent plays for every linked listener right now instead
  # of waiting for the schedule.
  class SyncsController < ApplicationController
    include AdminAuthenticated
    include CrossSiteGuarded

    # Triggered from a terminal or a cron-style hook, not from a browser form;
    # HTTP Basic auth is what guards it.
    skip_forgery_protection

    # Without the CSRF token, this is what stops a page the owner visits from
    # posting here on their behalf and burning the Spotify quota.
    before_action :reject_cross_site_requests

    def create
      accounts = SpotifyAccount.connected.to_a
      if accounts.empty?
        return render json: { error: "No Spotify account linked. Visit /spotify/connect." },
                      status: :precondition_required
      end

      # One listener's bad token must not hide everyone else's imports, so each
      # is reported on its own rather than aborting the batch.
      render json: { listeners: accounts.map { |account| sync(account) } }
    end

    private

    def sync(account)
      result = RecentlyPlayedSync.call(account)
      { id: account.id, name: account.display_name, imported: result.imported,
        last_played_at: result.latest_played_at }
    rescue Spotify::Error => e
      { id: account.id, name: account.display_name, error: e.message }
    end
  end
end
