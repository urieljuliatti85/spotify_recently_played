module Api
  class AlbumsController < BaseController
    def releases
      title = params[:title].to_s.strip
      artist = params[:artist].to_s.strip
      return render json: { releases: [] } if title.blank? || artist.blank?

      releases = Rails.cache.fetch("discogs:album_releases:#{title}:#{artist}", expires_in: 2.minutes) do
        DiscogsShelf::ReleaseFilter.call(shelf.album_releases(title, artist), title: title, artist: artist)
      end

      render json: { releases: releases }
    rescue DiscogsShelf::Error => e
      render json: { error: e.message }, status: :bad_gateway
    end

    def discogs
      match = DiscogsMatch.where(spotify_album_id: params[:id]).order(matched_at: :desc).first
      return render json: { url: nil } unless match

      render json: { url: "https://www.discogs.com/release/#{match.discogs_id}" }
    end

    def tracks
      payload = Rails.cache.fetch("spotify:album_tracks:#{params[:id]}", expires_in: 1.hour) do
        Spotify::Client.new.album(params[:id], market: Spotify.market)
      end

      # The "simplified" track objects nested under tracks.items don't repeat
      # the album's own name/id/images — it is the album — so that has to
      # come from the payload's own top level instead of from each track.
      tracks = Array(payload.dig("tracks", "items")).filter_map do |track|
        Spotify::TrackSerializer.call(track, album: payload, include_album_id: true)
      end
      render json: { tracks: tracks }
    rescue Spotify::NotFoundError
      render json: { error: "Album not found on Spotify" }, status: :not_found
    end

    private

    def shelf
      @shelf ||= DiscogsShelf::Client.new
    end
  end
end
