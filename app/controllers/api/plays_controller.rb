module Api
  # Public read-only feed of what the owner and their friends have been
  # listening to.
  class PlaysController < BaseController
    DEFAULT_LIMIT = 30
    MAX_LIMIT = 100

    def index
      plays = Play.on_the_feed
                  .by_listener(params[:listener])
                  .recent
                  .before(cursor)
                  .includes(:spotify_account, track: { track_artists: :artist })
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
      listener = play.spotify_account

      {
        id: play.id,
        played_at: play.played_at.iso8601(3),
        context_type: play.context_type,
        context_url: play.context_url,
        # Who played it. The feed mixes several people, so a row means nothing
        # without a name attached to it.
        listener: {
          id: listener.id,
          name: listener.display_name,
          avatar_url: listener.avatar_url,
          owner: listener.owner
        },
        track: {
          spotify_id: track.spotify_id,
          name: track.name,
          artists: track.artist_names,
          album: track.album_name,
          album_spotify_id: track.spotify_album_id,
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
