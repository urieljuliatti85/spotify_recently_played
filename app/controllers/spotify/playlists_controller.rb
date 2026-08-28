module Spotify
  # Owner-only: turn what this feed has never played into a public playlist on
  # the owner's account.
  #
  # Neither action can live under the public /api namespace. #unheard reads up
  # to MAX_ARTISTS top-track lists in a single call, which would let one public
  # request cost fifteen against the owner's quota, and #create writes to their
  # Spotify account outright.
  class PlaylistsController < ApplicationController
    include AdminAuthenticated
    include CrossSiteGuarded

    def search
      query = params[:q].to_s.strip
      return render json: { tracks: [] } if query.blank?

      payload = Client.new.search(query, type: "track", limit: 10, market: Spotify.market)
      render json: { tracks: Array(payload.dig("tracks", "items")).filter_map { |track| serialize_track(track) } }
    rescue NotConnectedError => e
      render json: { error: e.message }, status: :service_unavailable
    rescue Error => e
      render json: { error: reconnect_hint(e) }, status: :bad_gateway
    end

    # Unlike the sync route this one *is* posted from a browser — but from
    # fetch(), never from a form, so there is no CSRF token to carry. HTTP
    # Basic credentials get replayed by the browser on their own, which is what
    # the Sec-Fetch-Site check below is for; ApplicationController's
    # `allow_browser versions: :modern` is what guarantees the header is there.
    skip_forgery_protection
    before_action :reject_cross_site_requests

    def unheard
      render json: { tracks: UnheardTracks.call }
    rescue NotConnectedError => e
      render json: { error: e.message }, status: :service_unavailable
    rescue Error => e
      render json: { error: reconnect_hint(e) }, status: :bad_gateway
    end

    def create
      owner = SpotifyAccount.owner
      return render json: { error: "No Spotify account linked. Visit /spotify/connect." },
                    status: :precondition_required if owner.nil?

      playlist = PlaylistBuilder.call(owner: owner, name: params[:name], track_ids: params[:track_ids])
      render json: { playlist: playlist }, status: :created
    rescue PlaylistBuilder::BlankNameError, PlaylistBuilder::NoTracksError => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue NotConnectedError => e
      render json: { error: e.message }, status: :service_unavailable
    rescue Error => e
      render json: { error: reconnect_hint(e) }, status: :bad_gateway
    end

    private

    def serialize_track(track)
      TrackSerializer.call(track)&.merge(from: { name: "Search result" })
    end

    # A 403 here means one thing in practice: the account was linked before
    # playlist-modify-public was asked for, and the stored refresh token still
    # carries the old scopes.
    def reconnect_hint(error)
      return error.message unless error.status == 403

      "Spotify refused the write. Reconnect at /spotify/connect to grant playlist-modify-public."
    end
  end
end
