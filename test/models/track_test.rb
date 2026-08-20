require "test_helper"

class TrackTest < ActiveSupport::TestCase
  def payload(overrides = {})
    {
      "id" => "abc123",
      "name" => "Song",
      "artists" => [ { "id" => "a1", "name" => "First" }, { "id" => "a2", "name" => "Second" } ],
      "album" => {
        "name" => "Album",
        "images" => [
          { "url" => "big.jpg", "width" => 640 },
          { "url" => "medium.jpg", "width" => 300 },
          { "url" => "small.jpg", "width" => 64 }
        ]
      },
      "external_urls" => { "spotify" => "https://open.spotify.com/track/abc123" },
      "duration_ms" => 1000,
      "explicit" => true
    }.merge(overrides)
  end

  test "joins every artist name" do
    assert_equal "First, Second", Track.upsert_from_spotify!(payload).artist_names
  end

  test "prefers the mid-sized cover" do
    assert_equal "medium.jpg", Track.upsert_from_spotify!(payload).album_image_url
  end

  test "falls back to the smallest cover when no mid size exists" do
    album = { "name" => "Album", "images" => [ { "url" => "big.jpg", "width" => 640 } ] }
    assert_equal "big.jpg", Track.upsert_from_spotify!(payload("album" => album)).album_image_url
  end

  test "tolerates a track without cover art" do
    assert_nil Track.upsert_from_spotify!(payload("album" => { "name" => "Album", "images" => [] })).album_image_url
  end

  test "updates the existing row instead of duplicating it" do
    Track.upsert_from_spotify!(payload)
    Track.upsert_from_spotify!(payload("name" => "Renamed"))

    assert_equal 1, Track.where(spotify_id: "abc123").count
    assert_equal "Renamed", Track.find_by(spotify_id: "abc123").name
  end

  test "links one artist row per credit, in Spotify's order" do
    track = Track.upsert_from_spotify!(payload)

    assert_equal [ "First", "Second" ], track.track_artists.map { |c| c.artist.name }
    assert_equal [ 0, 1 ], track.track_artists.map(&:position)
  end

  # Order comes from the credit position, not from whichever artist row was
  # created first — a lead artist we already know keeps their billing.
  test "credit order follows the payload, not the artists' insertion order" do
    Track.upsert_from_spotify!(payload)
    flipped = [ { "id" => "a2", "name" => "Second" }, { "id" => "a1", "name" => "First" } ]
    track = Track.upsert_from_spotify!(payload("id" => "def456", "artists" => flipped))

    assert_equal [ "Second", "First" ], track.track_artists.map { |c| c.artist.name }
    assert_equal [ 0, 1 ], track.track_artists.map(&:position)
  end

  # The whole reason artists are modelled: splitting `artist_names` on commas
  # would tear this one name into two artists.
  test "a comma inside a name stays one artist" do
    artists = [ { "id" => "tyler", "name" => "Tyler, The Creator" } ]
    track = Track.upsert_from_spotify!(payload("artists" => artists))

    assert_equal [ "Tyler, The Creator" ], track.artists.map(&:name)
    assert_equal "Tyler, The Creator", track.artist_names
  end

  test "re-crediting a track drops the artist who is no longer on it" do
    track = Track.upsert_from_spotify!(payload)
    Track.upsert_from_spotify!(payload("artists" => [ { "id" => "a2", "name" => "Second" } ]))

    assert_equal [ "Second" ], track.reload.artists.map(&:name)
    assert_equal 2, Artist.count, "the dropped artist survives for their other tracks"
  end

  test "two tracks by the same artist share one artist row" do
    Track.upsert_from_spotify!(payload)
    Track.upsert_from_spotify!(payload("id" => "def456"))

    assert_equal 1, Artist.where(spotify_id: "a1").count
    assert_equal 2, Artist.find_by(spotify_id: "a1").tracks.count
  end

  # Simplified payloads sometimes omit ids; the display string still has to
  # survive, and the credits already linked must not be thrown away.
  test "an artist without an id is skipped rather than linked" do
    track = Track.upsert_from_spotify!(payload("artists" => [ { "name" => "Nameless" } ]))

    assert_empty track.artists
    assert_equal "Nameless", track.artist_names
  end

  test "an id-less payload leaves existing credits alone" do
    track = Track.upsert_from_spotify!(payload)
    Track.upsert_from_spotify!(payload("artists" => [ { "name" => "First" } ]))

    assert_equal [ "First", "Second" ], track.reload.artists.map(&:name)
  end

  test "destroying a track clears its credit links but not the artists" do
    track = Track.upsert_from_spotify!(payload)

    assert_difference -> { TrackArtist.count }, -2 do
      assert_no_difference -> { Artist.count } do
        track.destroy!
      end
    end
  end
end
