require "test_helper"

module Spotify
  class ReleaseMatcherTest < ActiveSupport::TestCase
    # A stand-in for Spotify::Client that answers from canned payloads and
    # counts what it was asked, so the request budget can be asserted.
    class FakeClient
      attr_reader :album_queries, :track_queries

      def initialize(albums: {}, album_detail: nil, tracks: {})
        @albums = albums
        @album_detail = album_detail
        @tracks = tracks
        @album_queries = []
        @track_queries = []
      end

      def search(query, type:, **)
        if type == "album"
          @album_queries << query
          { "albums" => { "items" => @albums.fetch(query, []) } }
        else
          @track_queries << query
          { "tracks" => { "items" => @tracks.fetch(query, []) } }
        end
      end

      def album(_id, **)
        @album_detail
      end
    end

    def album(name:, id: "album-1", artist: "Judas Priest", date: "1979-01-01")
      {
        "id" => id,
        "name" => name,
        "artists" => [ { "name" => artist } ],
        "release_date" => date,
        "images" => [ { "url" => "cover.jpg", "width" => 300 } ],
        "external_urls" => { "spotify" => "https://album" }
      }
    end

    def spotify_track(name, id: name.parameterize, playable: true)
      {
        "id" => id,
        "name" => name,
        "artists" => [ { "name" => "Judas Priest" } ],
        "duration_ms" => 200_000,
        "is_playable" => playable,
        "external_urls" => { "spotify" => "https://track/#{id}" }
      }
    end

    def release(tracklist, title: "Unleashed In The East (Live In Japan)", artist: "Judas Priest", year: 1979)
      {
        "discogs_id" => 1,
        "title" => title,
        "artist" => artist,
        "year" => year,
        "tracklist" => tracklist
      }
    end

    test "matches the album and maps tracks past translations and live suffixes" do
      client = FakeClient.new(
        albums: { %(album:"Unleashed In The East (Live In Japan)" artist:"Judas Priest") =>
                    [ album(name: "Unleashed In The East") ] },
        album_detail: { "tracks" => { "items" => [ spotify_track("Exciter - Live"),
                                                   spotify_track("Tyrant - Live") ] } }
      )

      result = ReleaseMatcher.call(
        release([ { "position" => "A1", "title" => "Exciter (Excitador)", "type" => "track" },
                  { "position" => "B4", "title" => "Tyrant (Tirano)", "type" => "track" } ]),
        client: client, market: "BR"
      )

      assert_equal "album-1", result.dig("album", "spotify_id")
      assert_equal 2, result["playable_count"]
      assert_equal [ "Exciter - Live", "Tyrant - Live" ], result["tracks"].map { |t| t.dig("track", "name") }
      assert_equal [ "album", "album" ], result["tracks"].map { |t| t["source"] }
      # The loose query is only tried when the filtered one comes up empty.
      assert_equal 1, client.album_queries.size
    end

    test "a Discogs translation after = does not confuse the title" do
      client = FakeClient.new(
        albums: { %(album:"Sad Wings" artist:"Judas Priest") => [ album(name: "Sad Wings") ] },
        album_detail: { "tracks" => { "items" => [ spotify_track("The Green Manalishi (With the Two Pronged Crown) - Live") ] } }
      )

      result = ReleaseMatcher.call(
        release([ { "position" => "A5",
                    "title" => %(The Green Manalishi (With The Two-Pronged Crown) = O "Manalishi" Verde),
                    "type" => "track" } ], title: "Sad Wings"),
        client: client, market: "BR"
      )

      assert_equal 1, result["playable_count"]
    end

    test "a different record by the same artist is not accepted" do
      client = FakeClient.new(
        albums: Hash.new([ album(name: "Painkiller") ]),
        album_detail: { "tracks" => { "items" => [] } }
      )

      result = ReleaseMatcher.call(
        release([ { "position" => "A1", "title" => "Exciter", "type" => "track" } ]),
        client: client, market: "BR"
      )

      assert_nil result["album"]
      assert_equal 0, result["playable_count"]
    end

    test "falls back to searching for tracks the album did not cover" do
      client = FakeClient.new(
        albums: {},
        tracks: { %(track:"Nemesis" artist:"Assassin") => [ spotify_track("Nemesis", id: "nem") ] }
      )

      result = ReleaseMatcher.call(
        release([ { "position" => "A2", "title" => "Nemesis", "type" => "track" } ],
                title: "The Upcoming Terror", artist: "Assassin"),
        client: client, market: "BR"
      )

      assert_nil result["album"]
      assert_equal "search", result["tracks"].first["source"]
      assert_equal "nem", result["tracks"].first.dig("track", "spotify_id")
    end

    test "the per-track fallback is capped" do
      client = FakeClient.new(albums: {})
      tracklist = (1..20).map { |i| { "position" => "A#{i}", "title" => "Song #{i}", "type" => "track" } }

      result = ReleaseMatcher.call(release(tracklist), client: client, market: "BR")

      assert_equal ReleaseMatcher::MAX_TRACK_SEARCHES, client.track_queries.size
      assert_equal 20, result["track_count"]
      assert_equal 0, result["playable_count"]
    end

    test "headings are not treated as tracks" do
      client = FakeClient.new(
        albums: { %(album:"Live" artist:"Judas Priest") => [ album(name: "Live") ] },
        album_detail: { "tracks" => { "items" => [ spotify_track("Exciter") ] } }
      )

      result = ReleaseMatcher.call(
        release([ { "position" => "", "title" => "Side A", "type" => "heading" },
                  { "position" => "A1", "title" => "Exciter", "type" => "track" } ], title: "Live"),
        client: client, market: "BR"
      )

      assert_equal 1, result["track_count"]
      assert_equal "Exciter", result["tracks"].first["title"]
    end

    test "a track Spotify reports as unplayable is not counted as playable" do
      client = FakeClient.new(
        albums: { %(album:"Live" artist:"Judas Priest") => [ album(name: "Live") ] },
        album_detail: { "tracks" => { "items" => [ spotify_track("Exciter", playable: false) ] } }
      )

      result = ReleaseMatcher.call(
        release([ { "position" => "A1", "title" => "Exciter", "type" => "track" } ], title: "Live"),
        client: client, market: "BR"
      )

      assert_equal 0, result["playable_count"]
      assert_equal false, result["tracks"].first.dig("track", "playable")
    end
  end
end
