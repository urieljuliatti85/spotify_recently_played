require "test_helper"

class ArtistTest < ActiveSupport::TestCase
  def payload(overrides = {})
    {
      "id" => "art1",
      "name" => "First",
      "external_urls" => { "spotify" => "https://open.spotify.com/artist/art1" }
    }.merge(overrides)
  end

  test "stores the artist from a Spotify payload" do
    artist = Artist.upsert_from_spotify!(payload)

    assert_equal "art1", artist.spotify_id
    assert_equal "First", artist.name
    assert_equal "https://open.spotify.com/artist/art1", artist.spotify_url
  end

  test "updates the existing row instead of duplicating it" do
    Artist.upsert_from_spotify!(payload)
    Artist.upsert_from_spotify!(payload("name" => "Renamed"))

    assert_equal 1, Artist.where(spotify_id: "art1").count
    assert_equal "Renamed", Artist.find_by(spotify_id: "art1").name
  end

  test "picks the mid-sized photo when a full payload carries images" do
    images = [ { "url" => "big.jpg", "width" => 640 }, { "url" => "medium.jpg", "width" => 320 } ]

    assert_equal "medium.jpg", Artist.upsert_from_spotify!(payload("images" => images)).image_url
  end

  # The artist objects nested inside a track have no images, and re-saving one
  # must not wipe a photo an earlier full payload already provided.
  test "keeps an existing photo when a simplified payload arrives" do
    images = [ { "url" => "medium.jpg", "width" => 320 } ]
    Artist.upsert_from_spotify!(payload("images" => images))

    assert_equal "medium.jpg", Artist.upsert_from_spotify!(payload).image_url
  end
end
