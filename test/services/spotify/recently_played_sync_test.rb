require "test_helper"

module Spotify
  class RecentlyPlayedSyncTest < ActiveSupport::TestCase
    # Stands in for Spotify::Client and records how it was called.
    class FakeClient
      attr_reader :calls, :artist_calls

      def initialize(pages, artists: [])
        @pages = Array(pages)
        @artists = artists
        @calls = []
        @artist_calls = []
      end

      def recently_played(after: nil, **)
        @calls << after
        { "items" => @pages.shift || [] }
      end

      def artists(ids)
        @artist_calls << Array(ids)
        @artists.select { |a| Array(ids).include?(a["id"]) }
      end
    end

    setup do
      @account = SpotifyAccount.create!(refresh_token: "r", access_token: "a",
                                        token_expires_at: 1.hour.from_now)
    end

    def item(spotify_id:, played_at:, name: "Song")
      {
        "played_at" => played_at.iso8601(3),
        "context" => { "type" => "playlist", "external_urls" => { "spotify" => "https://ctx" } },
        "track" => {
          "id" => spotify_id,
          "name" => name,
          "artists" => [ { "id" => "art1", "name" => "Artist" } ],
          "album" => { "name" => "Album", "images" => [] },
          "external_urls" => { "spotify" => "https://track" },
          "duration_ms" => 1000,
          "explicit" => false
        }
      }
    end

    test "imports plays and records the newest timestamp" do
      newest = 5.minutes.ago.round
      client = FakeClient.new([ [ item(spotify_id: "a", played_at: 1.hour.ago.round),
                                 item(spotify_id: "b", played_at: newest) ] ])

      result = RecentlyPlayedSync.new(@account, client:).call

      assert_equal 2, result.imported
      assert_equal 2, Play.count
      assert_equal newest, @account.reload.last_played_at
      assert_not_nil @account.last_synced_at
    end

    test "re-syncing the same window imports nothing twice" do
      played_at = 10.minutes.ago.round
      payload = [ item(spotify_id: "a", played_at: played_at) ]

      RecentlyPlayedSync.new(@account, client: FakeClient.new([ payload ])).call
      result = RecentlyPlayedSync.new(@account, client: FakeClient.new([ payload ])).call

      assert_equal 0, result.imported
      assert_equal 1, Play.count
    end

    # Spotify timestamps carry milliseconds, and telling plays apart is what
    # decides whether one gets imported. Two that share a second are still two.
    test "two plays milliseconds apart are both imported" do
      client = FakeClient.new([ [ item(spotify_id: "a", played_at: Time.utc(2026, 8, 21, 1, 4, 53, 133_000)),
                                 item(spotify_id: "b", played_at: Time.utc(2026, 8, 21, 1, 4, 53, 777_000)) ] ])

      result = RecentlyPlayedSync.new(@account, client:).call

      assert_equal 2, result.imported
      assert_equal 2, Play.count
    end

    test "asks Spotify only for plays after the last one it stored" do
      previous = 30.minutes.ago.round
      @account.update!(last_played_at: previous)
      client = FakeClient.new([ [] ])

      RecentlyPlayedSync.new(@account, client:).call

      assert_equal [ previous ], client.calls
    end

    test "the same track played twice yields two plays and one track" do
      client = FakeClient.new([ [ item(spotify_id: "a", played_at: 1.hour.ago.round),
                                 item(spotify_id: "a", played_at: 2.hours.ago.round) ] ])

      RecentlyPlayedSync.new(@account, client:).call

      assert_equal 2, Play.count
      assert_equal 1, Track.count
    end

    test "an empty response leaves the stored cursor alone" do
      previous = 30.minutes.ago.round
      @account.update!(last_played_at: previous)

      RecentlyPlayedSync.new(@account, client: FakeClient.new([ [] ])).call

      assert_equal previous, @account.reload.last_played_at
    end

    test "refuses to run without a linked account" do
      assert_raises(NotConnectedError) { RecentlyPlayedSync.new(nil) }
    end

    test "imported plays bring their artists with them" do
      client = FakeClient.new([ [ item(spotify_id: "a", played_at: 1.hour.ago.round) ] ])

      RecentlyPlayedSync.new(@account, client:).call

      assert_equal [ "Artist" ], Track.sole.artists.map(&:name)
      assert_equal "art1", Artist.sole.spotify_id
    end

    test "fetches a photo for an artist it has just met" do
      client = FakeClient.new(
        [ [ item(spotify_id: "a", played_at: 1.hour.ago.round) ] ],
        artists: [ { "id" => "art1", "name" => "Artist",
                     "images" => [ { "url" => "photo.jpg", "width" => 320 } ] } ]
      )

      RecentlyPlayedSync.new(@account, client:).call

      assert_equal [ [ "art1" ] ], client.artist_calls
      assert_equal "photo.jpg", Artist.sole.image_url
    end

    test "a sync that imports nothing does not go looking for photos" do
      client = FakeClient.new([ [] ])

      RecentlyPlayedSync.new(@account, client:).call

      assert_empty client.artist_calls
    end

    # The photo lookup is a nicety; losing it must never cost us the plays.
    test "keeps the imported plays when the photo lookup fails" do
      client = FakeClient.new([ [ item(spotify_id: "a", played_at: 1.hour.ago.round) ] ])
      client.define_singleton_method(:artists) { |_ids| raise Spotify::Error, "boom" }

      result = RecentlyPlayedSync.new(@account, client:).call

      assert_equal 1, result.imported
      assert_equal 1, Play.count
      assert_not_nil @account.reload.last_synced_at
    end
  end
end
