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

    # Spotify ids are 22 base62 characters. Anything else is not a track id,
    # and it is about to be interpolated into a URI.
    TRACK_ID = /\A[A-Za-z0-9]{22}\z/
    # Spotify's own ceilings on a playlist name and on one add request.
    NAME_LIMIT = 100
    MAX_TRACKS = 100

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

      name = params[:name].to_s.strip.first(NAME_LIMIT)
      return render json: { error: "Give the playlist a name." }, status: :unprocessable_entity if name.blank?

      ids = track_ids
      return render json: { error: "Pick at least one track." }, status: :unprocessable_entity if ids.empty?

      render json: { playlist: build(owner, name, ids) }, status: :created
    rescue NotConnectedError => e
      render json: { error: e.message }, status: :service_unavailable
    rescue Error => e
      render json: { error: reconnect_hint(e) }, status: :bad_gateway
    end

    private

    def track_ids
      Array(params[:track_ids]).map(&:to_s).uniq.select { |id| id.match?(TRACK_ID) }.first(MAX_TRACKS)
    end

    def build(owner, name, ids)
      client = Client.new(owner)
      playlist = client.create_playlist(name: name, description: description)
      client.add_playlist_items(playlist["id"], ids.map { |id| "spotify:track:#{id}" })

      # The playlists tab reads a five-minute cache. Without dropping it here,
      # the playlist the owner just built would not appear on the tab that
      # built it until that cache expired.
      Rails.cache.delete("spotify:playlists")

      {
        id: playlist["id"],
        name: playlist["name"],
        spotify_url: playlist.dig("external_urls", "spotify"),
        tracks_count: ids.size
      }
    end

    def description
      "Tracks from the artists on this feed that nobody here had played yet. " \
        "Built #{Time.current.strftime('%-d %b %Y')}."
    end

    def serialize_track(track)
      return if track.blank? || track["id"].blank? || track["name"].blank?

      {
        spotify_id: track["id"],
        name: track["name"],
        artists: Array(track["artists"]).map { |artist| artist["name"] }.join(", "),
        album: track.dig("album", "name"),
        album_image_url: Track.pick_image(track.dig("album", "images")),
        spotify_url: track.dig("external_urls", "spotify"),
        duration_ms: track["duration_ms"],
        explicit: track["explicit"] || false,
        from: { name: "Search result" }
      }
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
