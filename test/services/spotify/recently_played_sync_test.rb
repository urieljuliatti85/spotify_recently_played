require "test_helper"

module Spotify
  class RecentlyPlayedSyncTest < ActiveSupport::TestCase
    # Stands in for Spotify::Client and records how it was called.
    class FakeClient
      attr_reader :calls

      def initialize(pages)
        @pages = Array(pages)
        @calls = []
      end

      def recently_played(after: nil, **)
        @calls << after
        { "items" => @pages.shift || [] }
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
          "artists" => [ { "name" => "Artist" } ],
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
  end
end
