require "test_helper"

module Spotify
  # The controller tests each exercise one flag combination of this shared
  # serializer, but none pins the full contract — a default flipping by
  # accident would still pass every controller test that expects the field it
  # already has, and none of them assert on the field it must not have.
  class TrackSerializerTest < ActiveSupport::TestCase
    def track(overrides = {})
      {
        "id" => "track-1",
        "name" => "Song",
        "artists" => [ { "id" => "artist-1", "name" => "Artist", "external_urls" => { "spotify" => "https://a" } } ],
        "album" => { "name" => "Album", "id" => "album-1", "images" => [] },
        "external_urls" => { "spotify" => "https://track" },
        "duration_ms" => 1000,
        "explicit" => true
      }.merge(overrides)
    end

    test "serializes the fields every caller relies on" do
      result = TrackSerializer.call(track)

      assert_equal "track-1", result[:spotify_id]
      assert_equal "Song", result[:name]
      assert_equal "Artist", result[:artists]
      assert_equal "Album", result[:album]
      assert_equal "https://track", result[:spotify_url]
      assert_equal 1000, result[:duration_ms]
      assert_equal true, result[:explicit]
    end

    test "returns nil for a track missing an id or a name" do
      assert_nil TrackSerializer.call(track("id" => nil))
      assert_nil TrackSerializer.call(track("name" => ""))
      assert_nil TrackSerializer.call(nil)
    end

    test "falls back to the track's own nested album when none is given" do
      result = TrackSerializer.call(track)

      assert_equal "Album", result[:album]
    end

    test "an explicit album overrides the track's own nested one" do
      result = TrackSerializer.call(track, album: { "name" => "Compilation", "images" => [] })

      assert_equal "Compilation", result[:album]
    end

    test "omits album_spotify_id unless include_album_id is asked for" do
      assert_not TrackSerializer.call(track).key?(:album_spotify_id)
    end

    test "includes album_spotify_id when include_album_id is true" do
      result = TrackSerializer.call(track, include_album_id: true)

      assert_equal "album-1", result[:album_spotify_id]
    end

    test "omits artist_list unless artist_list is asked for" do
      assert_not TrackSerializer.call(track).key?(:artist_list)
    end

    test "builds artist_list, dropping credits without an id or a name, when asked for" do
      result = TrackSerializer.call(
        track("artists" => [
          { "id" => "artist-1", "name" => "Artist", "external_urls" => { "spotify" => "https://a" } },
          { "id" => "", "name" => "No id" }
        ]),
        artist_list: true
      )

      assert_equal [ { id: "artist-1", name: "Artist", url: "https://a" } ], result[:artist_list]
    end
  end
end
