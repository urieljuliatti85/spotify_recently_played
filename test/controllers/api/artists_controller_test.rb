require "test_helper"

module Api
  class ArtistsControllerTest < ActionDispatch::IntegrationTest
    test "returns tracks from Spotify for an artist" do
      Artist.create!(spotify_id: "artist-1", name: "Artist")

      searched_type = nil
      fake_client = Object.new
      fake_client.define_singleton_method(:search) do |_query, type:, market: nil|
        searched_type = type

        {
          "tracks" => {
            "items" => [
              {
                "id" => "track-1",
                "name" => "New song",
                "artists" => [
                  { "id" => "artist-1", "name" => "Artist", "external_urls" => { "spotify" => "artist-url" } }
                ],
                "album" => {
                  "name" => "New album",
                  "images" => [ { "url" => "cover.jpg", "width" => 300 } ]
                },
                "external_urls" => { "spotify" => "track-url" },
                "duration_ms" => 180_000,
                "explicit" => false
              },
              # Same name, different artist — the search matches on the name
              # alone, so this has to be filtered back out by credited id.
              {
                "id" => "track-2",
                "name" => "Namesake's song",
                "artists" => [ { "id" => "artist-2", "name" => "Artist" } ],
                "album" => { "name" => "Other album", "images" => [] },
                "duration_ms" => 200_000
              }
            ]
          }
        }
      end

      stubbing(Spotify::Client, :new, fake_client) do
        get api_artist_tracks_path("artist-1")
      end

      assert_response :success
      assert_equal "track", searched_type
      tracks = response.parsed_body["tracks"]
      assert_equal 1, tracks.length
      track = tracks.first
      assert_equal "New song", track["name"]
      assert_equal "New album", track["album"]
      assert_equal "cover.jpg", track["album_image_url"]
      assert_equal "artist-1", track["artist_list"].first["id"]
    end

    test "falls back to a single-resource lookup for an artist the app has never seen" do
      fetched_ids = nil
      searched_query = nil
      fake_client = Object.new
      fake_client.define_singleton_method(:artists) do |ids|
        fetched_ids = ids
        [ { "id" => "artist-9", "name" => "Unknown Artist" } ]
      end
      fake_client.define_singleton_method(:search) do |query, type:, market: nil|
        searched_query = query
        { "tracks" => { "items" => [] } }
      end

      stubbing(Spotify::Client, :new, fake_client) do
        get api_artist_tracks_path("artist-9")
      end

      assert_response :success
      assert_empty response.parsed_body["tracks"]
      assert_equal [ "artist-9" ], fetched_ids
      assert_equal %(artist:"Unknown Artist"), searched_query
    end

    test "reports 404 when the artist is unknown locally and on Spotify" do
      fake_client = Object.new
      fake_client.define_singleton_method(:artists) { |_ids| [] }

      stubbing(Spotify::Client, :new, fake_client) do
        get api_artist_tracks_path("artist-9")
      end

      assert_response :not_found
    end

    test "reports when Spotify is not connected" do
      get api_artist_tracks_path("artist-1")

      assert_response :service_unavailable
      assert_equal "No Spotify account linked yet", response.parsed_body["error"]
    end
  end
end
