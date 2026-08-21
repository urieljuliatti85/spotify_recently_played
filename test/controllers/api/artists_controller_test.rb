require "test_helper"

module Api
  class ArtistsControllerTest < ActionDispatch::IntegrationTest
    test "returns tracks from Spotify for an artist" do
      fake_client = Object.new
      fake_client.define_singleton_method(:artist_top_tracks) do |_id|
        {
          "tracks" => [
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
            }
          ]
        }
      end

      stubbing(Spotify::Client, :new, fake_client) do
        get api_artist_tracks_path("artist-1")
      end

      assert_response :success
      track = response.parsed_body["tracks"].first
      assert_equal "New song", track["name"]
      assert_equal "New album", track["album"]
      assert_equal "cover.jpg", track["album_image_url"]
      assert_equal "artist-1", track["artist_list"].first["id"]
    end

    test "reports when Spotify is not connected" do
      get api_artist_tracks_path("artist-1")

      assert_response :service_unavailable
      assert_equal "No Spotify account linked yet", response.parsed_body["error"]
    end
  end
end
