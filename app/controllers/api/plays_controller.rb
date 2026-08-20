module Api
  # Public read-only feed of what the owner has been listening to.
  class PlaysController < BaseController
    DEFAULT_LIMIT = 30
    MAX_LIMIT = 100

    def index
      plays = Play.recent
                  .before(cursor)
                  .includes(track: { track_artists: :artist })
                  .limit(limit + 1)
                  .to_a

      has_more = plays.size > limit
      plays = plays.first(limit)

      render json: {
        plays: plays.map { |play| serialize(play) },
        next_cursor: has_more ? plays.last.played_at.iso8601(3) : nil
      }
    end

    private

    def limit
      requested = params[:limit].presence&.to_i
      return DEFAULT_LIMIT if requested.nil? || requested <= 0

      requested.clamp(1, MAX_LIMIT)
    end

    def cursor
      return nil if params[:before].blank?

      Time.iso8601(params[:before])
    rescue ArgumentError
      nil
    end

    def serialize(play)
      track = play.track

      {
        id: play.id,
        played_at: play.played_at.iso8601(3),
        context_type: play.context_type,
        context_url: play.context_url,
        track: {
          spotify_id: track.spotify_id,
          name: track.name,
          artists: track.artist_names,
          album: track.album_name,
          album_image_url: track.album_image_url,
          spotify_url: track.spotify_url,
          duration_ms: track.duration_ms,
          explicit: track.explicit,
          # `artists` stays the display string; this is the same credit list
          # split into addressable records, in Spotify's order.
          artist_list: track.track_artists.map do |credit|
            artist = credit.artist
            {
              id: artist.spotify_id,
              name: artist.name,
              url: artist.spotify_url,
              image_url: artist.image_url
            }
          end
        }
      }
    end
  end
end
