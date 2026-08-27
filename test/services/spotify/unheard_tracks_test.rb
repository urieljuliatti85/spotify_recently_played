require "test_helper"

module Spotify
  class UnheardTracksTest < ActiveSupport::TestCase
    # A stand-in for Spotify::Client that answers canned searches and records
    # every query, so the request budget can be asserted.
    class FakeClient
      attr_reader :queries

      def initialize(results = {}, raises: {})
        @results = results
        @raises = raises
        @queries = []
      end

      def search(query, **)
        @queries << query
        raise @raises[query] if @raises.key?(query)

        { "tracks" => { "items" => @results.fetch(query, []) } }
      end
    end

    def setup
      @account = SpotifyAccount.create!(spotify_user_id: "owner-1", owner: true)
      # played_at is unique per listener, so every play in a test needs its own
      # instant rather than sharing "now".
      @minute = 0
    end

    # One artist credited on one track, played `plays` times.
    def artist_on_the_feed(name, id:, plays: 1)
      track = Track.create!(spotify_id: "heard-#{id}", name: "Heard #{name}", artist_names: name)
      artist = Artist.create!(spotify_id: id, name: name)
      TrackArtist.create!(track: track, artist: artist, position: 0)
      plays.times { Play.create!(track: track, spotify_account: @account, played_at: (@minute += 1).minutes.ago) }
      artist
    end

    def hit(id, name, artist_ids)
      {
        "id" => id,
        "name" => name,
        "artists" => artist_ids.map { |artist_id| { "id" => artist_id, "name" => artist_id } },
        "album" => { "name" => "An album", "images" => [ { "url" => "cover.jpg", "width" => 300 } ] },
        "external_urls" => { "spotify" => "https://track" },
        "duration_ms" => 1000
      }
    end

    test "leaves out what the feed has already played" do
      artist_on_the_feed("Dodsrit", id: "a1")
      client = FakeClient.new(
        { %(artist:"Dodsrit") => [ hit("heard-a1", "Heard Dodsrit", [ "a1" ]), hit("new-1", "Nocturnal Will", [ "a1" ]) ] }
      )

      tracks = UnheardTracks.new(client: client).call

      assert_equal [ "new-1" ], tracks.map { |track| track[:spotify_id] }
      assert_equal({ id: "a1", name: "Dodsrit" }, tracks.first[:from])
    end

    test "ignores a hit that is not credited to the artist it searched for" do
      artist_on_the_feed("Silver", id: "a1")
      client = FakeClient.new({ %(artist:"Silver") => [ hit("other-1", "By a different Silver", [ "someone-else" ]) ] })

      assert_empty UnheardTracks.new(client: client).call
    end

    test "a track two artists both return is only offered once" do
      artist_on_the_feed("Split A", id: "a1", plays: 2)
      artist_on_the_feed("Split B", id: "a2", plays: 1)
      shared = hit("shared-1", "A split", [ "a1", "a2" ])
      client = FakeClient.new({ %(artist:"Split A") => [ shared ], %(artist:"Split B") => [ shared ] })

      assert_equal [ "shared-1" ], UnheardTracks.new(client: client).call.map { |track| track[:spotify_id] }
    end

    test "walks the most played artists first and stops at the ceiling" do
      artist_on_the_feed("Quiet", id: "a1", plays: 1)
      artist_on_the_feed("Loud", id: "a2", plays: 9)
      client = FakeClient.new

      UnheardTracks.new(client: client, artists: 1).call

      assert_equal [ %(artist:"Loud") ], client.queries
    end

    test "one artist Spotify has lost does not empty the list" do
      artist_on_the_feed("Gone", id: "a1", plays: 9)
      artist_on_the_feed("Here", id: "a2", plays: 1)
      client = FakeClient.new(
        { %(artist:"Here") => [ hit("new-1", "Still here", [ "a2" ]) ] },
        raises: { %(artist:"Gone") => NotFoundError.new("gone", status: 404) }
      )

      assert_equal [ "new-1" ], UnheardTracks.new(client: client).call.map { |track| track[:spotify_id] }
    end

    test "a rate limit stops the walk instead of being swallowed once per artist" do
      artist_on_the_feed("First", id: "a1", plays: 9)
      artist_on_the_feed("Second", id: "a2", plays: 1)
      client = FakeClient.new({}, raises: { %(artist:"First") => RateLimitedError.new("slow down", status: 429) })

      assert_raises(RateLimitedError) { UnheardTracks.new(client: client).call }
      assert_equal [ %(artist:"First") ], client.queries
    end
  end
end
