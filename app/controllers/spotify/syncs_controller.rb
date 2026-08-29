module Spotify
  # Public: pull recent plays for every linked listener right now instead of
  # waiting for the schedule. No ADMIN_PASSWORD required — anyone can press
  # the Sync button. One call here still means one Spotify request per
  # connected account, though, so the rate limit below is what stands between
  # that and burning through Spotify's quota (see CrossSiteGuarded below for
  # the other half: stopping a page from doing this on a visitor's behalf).
  class SyncsController < ApplicationController
    include CrossSiteGuarded

    rate_limit to: 5, within: 1.minute,
               with: -> { render json: { error: "Too many requests" }, status: :too_many_requests }

    # Triggered from a terminal or a cron-style hook, not from a browser form.
    skip_forgery_protection

    # What stops a page the owner (or anyone) visits from posting here on
    # their behalf and burning the Spotify quota, now that this needs no
    # credential of its own to check instead.
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
