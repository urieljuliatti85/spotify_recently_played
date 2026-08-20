module Spotify
  # Owner-only: pull recent plays right now instead of waiting for the schedule.
  class SyncsController < ApplicationController
    include AdminAuthenticated

    # Triggered from a terminal or a cron-style hook, not from a browser form;
    # HTTP Basic auth is what guards it.
    skip_forgery_protection

    def create
      result = RecentlyPlayedSync.call
      render json: { imported: result.imported, last_played_at: result.latest_played_at }
    rescue NotConnectedError
      render json: { error: "No Spotify account linked. Visit /spotify/connect." }, status: :precondition_required
    rescue Spotify::Error => e
      render json: { error: e.message }, status: :bad_gateway
    end
  end
end
