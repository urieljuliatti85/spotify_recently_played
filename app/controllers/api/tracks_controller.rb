module Api
  class TracksController < BaseController
    # A page of the feed can carry many distinct tracks; searching YouTube for
    # every one of them on a single request could burn through a day's quota
    # (100 units per search, 10,000/day default) in one page load. This caps
    # how many *new* lookups one request is allowed to spend — already-cached
    # tracks are still returned in full.
    MAX_RESOLVES = 5
    MAX_IDS = 40

    # Batched so the feed can ask about everything on screen in one request
    # instead of one round trip per row.
    def youtube_matches
      ids = params[:ids].to_s.split(",").map(&:strip).reject(&:blank?).uniq.first(MAX_IDS)
      return render json: { matches: {} } if ids.empty?

      tracks = Track.where(spotify_id: ids).index_by(&:spotify_id)
      cached = YoutubeMatch.for_ids(ids).index_by(&:spotify_track_id)

      # Without a key nothing new can be resolved, but a match some earlier,
      # configured visitor already paid for is still worth serving.
      resolves = Youtube.configured? ? 0 : MAX_RESOLVES
      matches = ids.filter_map do |id|
        track = tracks[id] or next
        match = cached[id]

        if match&.fresh?
          match
        elsif resolves < MAX_RESOLVES
          resolves += 1
          YoutubeMatch.resolve(track)
        end
      end

      # A resolved match answers with a url (found) or null (checked, no clip)
      # — either way the caller should stop asking. An id simply missing from
      # this hash is the third state: still unresolved because this request
      # hit the cap, and worth asking about again later.
      render json: { matches: matches.to_h { |match| [ match.spotify_track_id, match.video_url ] } }
    end

    # Single-track, unlike youtube_matches: the PlayerBar only ever asks
    # about whatever is currently playing, and lrclib has no daily quota to
    # protect — so there is no need to batch or cap this one.
    def lyrics
      track = Track.find_by(spotify_id: params[:id])
      return render json: { found: false, instrumental: false, plain_lyrics: nil, synced_lyrics: nil } unless track

      render json: Lyric.resolve(track).summary
    end
  end
end
