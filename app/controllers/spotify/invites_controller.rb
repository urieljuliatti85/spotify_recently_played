module Spotify
  # Owner-only: issue the links friends use to add themselves.
  class InvitesController < ApplicationController
    include AdminAuthenticated
    include CrossSiteGuarded

    skip_forgery_protection

    before_action :reject_cross_site_requests, except: :index

    def index
      render plain: Invite.order(created_at: :desc).map { |invite| describe(invite) }.join("\n").presence ||
                    "No invites yet. POST to /spotify/invites to issue one."
    end

    def create
      invite = Invite.issue!(label: params[:label])

      # The only time the raw token exists outside the friend's browser.
      render json: {
        invite_url: join_url(invite.token),
        expires_at: invite.expires_at.iso8601
      }, status: :created
    end

    def destroy
      Invite.find_by(id: params[:id])&.destroy
      head :no_content
    end

    private

    def describe(invite)
      state = if invite.claimed?  then "claimed by #{invite.spotify_account&.display_name || 'a deleted account'}"
      elsif invite.expired? then "expired"
      else "open until #{invite.expires_at.iso8601}"
      end

      "##{invite.id} #{invite.label || '(no label)'} — #{state}"
    end

    def join_url(token)
      spotify_join_url(token: token, host: URI.parse(Spotify.redirect_uri).authority,
                       protocol: URI.parse(Spotify.redirect_uri).scheme)
    end
  end
end
