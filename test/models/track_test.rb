require "test_helper"

class TrackTest < ActiveSupport::TestCase
  def payload(overrides = {})
    {
      "id" => "abc123",
      "name" => "Song",
      "artists" => [ { "name" => "First" }, { "name" => "Second" } ],
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
end
