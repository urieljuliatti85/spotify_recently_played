module Spotify
  # Owner-only: pull recent plays right now instead of waiting for the schedule.
  class SyncsController < ApplicationController
    include AdminAuthenticated

    # Triggered from a terminal or a cron-style hook, not from a browser form;
    # HTTP Basic auth is what guards it.
    skip_forgery_protection

    # With the CSRF token out of the picture, HTTP Basic alone is not enough:
    # a browser replays those credentials on its own, so any page the owner
    # visits afterwards could post here and burn the Spotify quota. Real
    # callers (curl, cron) send no Sec-Fetch-Site header at all; a cross-site
    # form post always does, and that is the difference this checks.
    before_action :reject_cross_site_requests

    def create
      result = RecentlyPlayedSync.call
      render json: { imported: result.imported, last_played_at: result.latest_played_at }
    rescue NotConnectedError
      render json: { error: "No Spotify account linked. Visit /spotify/connect." }, status: :precondition_required
    rescue Spotify::Error => e
      render json: { error: e.message }, status: :bad_gateway
    end

    private

    def reject_cross_site_requests
      site = request.headers["Sec-Fetch-Site"]
      return if site.blank? || site == "same-origin"

      head :forbidden
    end
  end
end
