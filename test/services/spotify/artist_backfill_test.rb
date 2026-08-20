require "test_helper"

module Spotify
  class ArtistBackfillTest < ActiveSupport::TestCase
    # Stands in for Spotify::Client and records the ids it was asked for.
    class FakeClient
      attr_reader :track_calls, :artist_calls

      def initialize(tracks: [], artists: [])
        @tracks = tracks
        @artists = artists
        @track_calls = []
        @artist_calls = []
      end

      def tracks(ids)
        @track_calls << Array(ids)
        @tracks.select { |t| Array(ids).include?(t["id"]) }
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

    # A row stored before artists were modelled: credits live only in the string.
    def legacy_track(spotify_id: "t1", artist_names: "Tyler, The Creator")
      Track.create!(spotify_id:, name: "Song", artist_names:)
    end

    def track_payload(id: "t1", artists: [ { "id" => "tyler", "name" => "Tyler, The Creator" } ])
      { "id" => id, "name" => "Song", "artists" => artists }
    end

    test "recovers credits a comma-joined string could not have been split into" do
      track = legacy_track
      client = FakeClient.new(tracks: [ track_payload ])

      result = ArtistBackfill.new(@account, client:).call

      assert_equal 1, result.linked_tracks
      assert_equal [ "Tyler, The Creator" ], track.reload.artists.map(&:name)
      assert_equal [ "tyler" ], track.artists.map(&:spotify_id)
    end

    test "asks only about tracks that have no credits yet" do
      legacy_track(spotify_id: "t1")
      linked = Track.upsert_from_spotify!(track_payload(id: "t2", artists: [ { "id" => "a1", "name" => "A" } ]))
      client = FakeClient.new(tracks: [ track_payload ])

      ArtistBackfill.new(@account, client:).call

      assert_equal [ [ "t1" ] ], client.track_calls
      assert_not_includes client.track_calls.flatten, linked.spotify_id
    end

    test "fetches the photos that simplified artist payloads never carry" do
      Track.upsert_from_spotify!(track_payload(artists: [ { "id" => "tyler", "name" => "Tyler" } ]))
      assert_nil Artist.find_by(spotify_id: "tyler").image_url

      client = FakeClient.new(
        artists: [ { "id" => "tyler", "name" => "Tyler",
                     "images" => [ { "url" => "photo.jpg", "width" => 320 } ] } ]
      )
      result = ArtistBackfill.new(@account, client:).call

      assert_equal 1, result.imaged_artists
      assert_equal "photo.jpg", Artist.find_by(spotify_id: "tyler").image_url
    end

    test "issues no requests at all once every row is filled in" do
      Track.upsert_from_spotify!(track_payload(artists: [ { "id" => "tyler", "name" => "Tyler" } ]))
      Artist.find_by(spotify_id: "tyler").update!(image_url: "photo.jpg")
      client = FakeClient.new

      result = ArtistBackfill.new(@account, client:).call

      assert_empty client.track_calls
      assert_empty client.artist_calls
      assert_equal 0, result.linked_tracks
      assert_equal 0, result.imaged_artists
    end

    test "leaves a track Spotify no longer knows about alone" do
      track = legacy_track
      client = FakeClient.new(tracks: [])

      result = ArtistBackfill.new(@account, client:).call

      assert_equal 0, result.linked_tracks
      assert_empty track.reload.artists
      assert_equal "Tyler, The Creator", track.artist_names, "the display string still stands in"
    end

    test "max_batches caps how much one call takes on" do
      (ArtistBackfill::BATCH + 1).times { |i| legacy_track(spotify_id: "t#{i}") }
      payloads = (ArtistBackfill::BATCH + 1).times.map { |i| track_payload(id: "t#{i}") }
      client = FakeClient.new(tracks: payloads)

      linked = ArtistBackfill.new(@account, client:).link_tracks(max_batches: 1)

      assert_equal ArtistBackfill::BATCH, linked
      assert_equal 1, client.track_calls.size
    end
  end
end
