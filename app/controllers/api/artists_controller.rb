module Api
  class ArtistsController < BaseController
    # An artist's top tracks barely change from hour to hour, and this route is
    # public: without the cache every visitor costs one Spotify request against
    # the owner's quota. A failure raises out of `fetch`, so only real payloads
    # are ever stored.
    #
    # Spotify's own /v1/artists/{id}/top-tracks answers 403 for this app, so
    # this asks the catalogue search for the artist's name instead — the same
    # workaround Spotify::UnheardTracks already uses for the same reason.
    def tracks
      payload = Rails.cache.fetch("spotify:artist_top_tracks:#{params[:id]}", expires_in: 1.hour) do
        client = Spotify::Client.new
        client.search(%(artist:"#{artist_name(client)}"), type: "track", market: Spotify.market)
      end

      # The search filters by name, so an artist who shares one with somebody
      # else comes back mixed in. The credited id is what settles it.
      tracks = Array(payload.dig("tracks", "items")).select do |track|
        Array(track["artists"]).any? { |credit| credit["id"] == params[:id] }
      end

      render json: {
        tracks: tracks.filter_map { |track| Spotify::TrackSerializer.call(track, artist_list: true) }
      }
    rescue Spotify::NotFoundError
      render json: { error: "Artist not found on Spotify" }, status: :not_found
    end

    private

    # The search needs a name to filter by. Artist already has it locally for
    # anyone who has shown up in the feed; a visitor following a link to an
    # artist this app has never seen falls back to the single-resource lookup
    # (allowed — only the ?ids= batch form of this endpoint is blocked).
    def artist_name(client)
      local = Artist.find_by(spotify_id: params[:id])&.name
      return local if local.present?

      fetched = client.artists([ params[:id] ]).first
      raise Spotify::NotFoundError, "Spotify has no such resource" if fetched.blank?

      fetched["name"]
    end
  end
end
