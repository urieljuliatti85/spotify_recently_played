module Spotify
  # Builds a public playlist on the owner's account from a set of track ids.
  # The only place in this app that writes a playlist, so validating the name,
  # dropping anything that is not a well-formed Spotify track id, and
  # invalidating the playlists tab's cache all live here rather than in the
  # controller.
  class PlaylistBuilder
    # Spotify ids are 22 base62 characters. Anything else is not a track id,
    # and it is about to be interpolated into a URI.
    TRACK_ID = /\A[A-Za-z0-9]{22}\z/
    # Spotify's own ceilings on a playlist name and on one add request.
    NAME_LIMIT = 100
    MAX_TRACKS = 100

    BlankNameError = Class.new(StandardError)
    NoTracksError = Class.new(StandardError)

    def self.call(...) = new(...).call

    def initialize(owner:, name:, track_ids:)
      @owner = owner
      @name = name.to_s.strip.first(NAME_LIMIT)
      @track_ids = Array(track_ids).map(&:to_s).uniq.select { |id| id.match?(TRACK_ID) }.first(MAX_TRACKS)
    end

    def call
      raise BlankNameError, "Give the playlist a name." if @name.blank?
      raise NoTracksError, "Pick at least one track." if @track_ids.empty?

      client = Client.new(@owner)
      playlist = client.create_playlist(name: @name, description: description)
      client.add_playlist_items(playlist["id"], @track_ids.map { |id| "spotify:track:#{id}" })

      # The playlists tab reads a five-minute cache. Without dropping it here,
      # the playlist just built would not appear on the tab that built it
      # until that cache expired.
      Rails.cache.delete("spotify:playlists")

      {
        id: playlist["id"],
        name: playlist["name"],
        spotify_url: playlist.dig("external_urls", "spotify"),
        tracks_count: @track_ids.size
      }
    end

    private

    def description
      "Tracks from the artists on this feed that nobody here had played yet. " \
        "Built #{Time.current.strftime('%-d %b %Y')}."
    end
  end
end
