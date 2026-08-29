module Youtube
  # Looks up the official video clip for a track by text search — YouTube and
  # Spotify share no identifier, so artist + title is all there is to go on.
  # Callers are expected to cache the result (see YoutubeMatch); this is not
  # cheap enough to run on a list endpoint.
  class ClipMatcher
    def self.call(...) = new(...).call

    def initialize(track, client: Client.new)
      @track = track
      @client = client
    end

    # The video id, or nil when nothing on YouTube looked like a match. Never
    # raises Youtube::Error: a lookup failure reads the same as "no clip
    # found" to a caller that only wants a link when one is safe to show.
    def call
      video = client.search(query)
      video&.dig("id", "videoId")
    rescue Error => e
      Rails.logger.warn("[Youtube] search failed for #{track.spotify_id}: #{e.message}")
      nil
    end

    private

    attr_reader :track, :client

    def query
      "#{track.artist_names} - #{track.name} (Official Video)"
    end
  end
end
