module Spotify
  # Owner-only: links (and unlinks) the one Spotify account this site mirrors.
  class SessionsController < ApplicationController
    include AdminAuthenticated

    # The callback comes back from Spotify's domain, so the CSRF token is gone;
    # the `state` parameter is what protects this exchange.
    skip_forgery_protection only: :create

    def new
      unless Spotify.configured?
        return render plain: "Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET first.",
                      status: :service_unavailable
      end

      state = SecureRandom.hex(16)
      session[:spotify_oauth_state] = state

      redirect_to Authorization.authorize_url(state: state), allow_other_host: true
    end

    def create
      expected_state = session.delete(:spotify_oauth_state)

      if params[:error].present?
        # Spotify's reason is worth having, but it arrives as an arbitrary query
        # parameter — it belongs in the log, not echoed back to the caller.
        Rails.logger.info("[spotify] authorization denied: #{params[:error]}")
        return render plain: "Spotify denied the request. Start again at /spotify/connect.", status: :bad_request
      end

      if expected_state.blank? || !ActiveSupport::SecurityUtils.secure_compare(params[:state].to_s, expected_state)
        return render plain: "Invalid OAuth state. Start again at /spotify/connect.", status: :bad_request
      end

      tokens = Authorization.exchange_code(params[:code])
      account = store_tokens(tokens)
      SyncRecentlyPlayedJob.perform_later

      redirect_to root_path, notice: "Connected as #{account.display_name}."
    rescue Spotify::Error => e
      render plain: "Could not connect: #{e.message}", status: :bad_gateway
    end

    def destroy
      SpotifyAccount.current&.destroy
      redirect_to root_path, notice: "Spotify account unlinked."
    end

    private

    def store_tokens(tokens)
      account = SpotifyAccount.current || SpotifyAccount.new
      account.update!(
        access_token: tokens["access_token"],
        refresh_token: tokens["refresh_token"],
        token_expires_at: tokens["expires_in"].to_i.seconds.from_now,
        scope: tokens["scope"]
      )

      profile = Client.new(account).me
      account.update!(spotify_user_id: profile["id"], display_name: profile["display_name"].presence || profile["id"])
      account
    end
  end
end
