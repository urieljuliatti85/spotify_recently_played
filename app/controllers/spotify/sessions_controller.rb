module Spotify
  # Links (and unlinks) the accounts this site mirrors. The owner links their
  # own from an admin-guarded route; a friend links theirs by claiming an
  # invite, which is what keeps ADMIN_PASSWORD out of a friend's hands.
  class SessionsController < ApplicationController
    include AdminAuthenticated

    # `join` carries its own credential (the invite token) and `create` is
    # reached from Spotify's domain, where no admin header survives. Both are
    # guarded by what the session recorded when the flow started.
    skip_before_action :authenticate_admin!, only: [ :join, :create ]

    # The callback comes back from Spotify's domain, so the CSRF token is gone;
    # the `state` parameter is what protects this exchange.
    skip_forgery_protection only: :create

    def new
      return unless credentials_present?

      begin_authorization(invite: nil)
    end

    # A friend's way in. The token is single-use and expiring; it is checked
    # here so a dead link fails before anyone is sent to Spotify, and again
    # after the callback so a link cannot be claimed twice by racing it.
    def join
      invite = Invite.claimable_by(params[:token])

      if invite.nil?
        return render plain: "This invite link is invalid, already used, or expired. Ask for a new one.",
                      status: :not_found
      end

      return unless credentials_present?

      begin_authorization(invite: invite)
    end

    def create
      expected_state = session.delete(:spotify_oauth_state)
      invite_id = session.delete(:spotify_invite_id)

      if params[:error].present?
        # Spotify's reason is worth having, but it arrives as an arbitrary query
        # parameter — it belongs in the log, not echoed back to the caller.
        Rails.logger.info("[spotify] authorization denied: #{params[:error].to_s.inspect}")
        return render plain: "Spotify denied the request. Start again at /spotify/connect.", status: :bad_request
      end

      if expected_state.blank? || !ActiveSupport::SecurityUtils.secure_compare(params[:state].to_s, expected_state)
        return render plain: "Invalid OAuth state. Start again at /spotify/connect.", status: :bad_request
      end

      invite = invite_id && Invite.claimable.find_by(id: invite_id)
      if invite_id && invite.nil?
        return render plain: "That invite was used or expired while you were away. Ask for a new one.",
                      status: :gone
      end

      account = link_account(tokens: Authorization.exchange_code(params[:code]), invite: invite)
      SyncRecentlyPlayedJob.perform_later(account)

      redirect_to root_path, notice: "Connected as #{account.display_name}."
    rescue Spotify::Error => e
      render plain: "Could not connect: #{e.message}", status: :bad_gateway
    end

    # Owner-only. Unlinking takes the listener's history with it, which is the
    # point: it is how someone comes off the page entirely.
    def destroy
      account = params[:id].present? ? SpotifyAccount.find_by(id: params[:id]) : SpotifyAccount.owner
      account&.destroy

      redirect_to root_path, notice: account ? "#{account.display_name} unlinked." : "Nothing to unlink."
    end

    private

    def credentials_present?
      return true if Spotify.configured?

      render plain: "Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET first.", status: :service_unavailable
      false
    end

    def begin_authorization(invite:)
      state = SecureRandom.hex(16)
      session[:spotify_oauth_state] = state
      session[:spotify_invite_id] = invite&.id

      scopes = invite ? Spotify::FRIEND_SCOPES : Spotify::SCOPES
      redirect_to Authorization.authorize_url(state: state, scopes: scopes), allow_other_host: true
    end

    # Which row the tokens belong to is decided by who Spotify says just
    # authorized, not by who started the flow — otherwise a friend's callback
    # could land on the owner's row. Asking `/me` needs a token but no stored
    # account, hence the bare-token client.
    def link_account(tokens:, invite:)
      profile = Client.with_token(tokens["access_token"]).me
      account = SpotifyAccount.find_or_initialize_by(spotify_user_id: profile["id"])

      SpotifyAccount.transaction do
        account.update!(
          access_token: tokens["access_token"],
          refresh_token: tokens["refresh_token"],
          token_expires_at: tokens["expires_in"].to_i.seconds.from_now,
          scope: tokens["scope"],
          display_name: profile["display_name"].presence || profile["id"],
          avatar_url: Track.pick_image(profile["images"]),
          # The first account to link owns the site; an invite never grants that.
          owner: account.owner? || (invite.nil? && SpotifyAccount.owner.nil?)
        )

        invite&.claim!(account)
      end

      account
    end
  end
end
