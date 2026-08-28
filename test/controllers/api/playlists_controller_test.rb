require "test_helper"

module Api
  class PlaylistsControllerTest < ActionDispatch::IntegrationTest
    test "returns only public playlists" do
      SpotifyAccount.create!(spotify_user_id: "user-1")
      fake_client = Object.new
      fake_client.define_singleton_method(:playlists) do
        {
          "items" => [
            {
              "id" => "public-1",
              "name" => "Public set",
              "public" => true,
              "owner" => { "id" => "user-1" },
              "images" => [ { "url" => "playlist.jpg", "width" => 300 } ],
              "external_urls" => { "spotify" => "https://playlist" },
              "items" => { "total" => 4 }
            },
            { "id" => "private-1", "name" => "Private set", "public" => false }
          ]
        }
      end

      stubbing(Spotify::Client, :new, fake_client) do
        get api_playlists_path
      end

      assert_response :success
      playlists = response.parsed_body["playlists"]
      assert_equal [ "public-1" ], playlists.map { |playlist| playlist["id"] }
      assert_equal "playlist.jpg", playlists.first["image_url"]
      assert_equal 4, playlists.first["tracks_count"]
    end

    test "returns a playlist's own name and cover alongside its playable tracks" do
      fake_client = Object.new
      # Despite what the reference docs call it, Spotify actually nests this
      # under "items", not "tracks" — verified against the real API.
      fake_client.define_singleton_method(:playlist) do |_id, market: nil|
        {
          "id" => "public-1",
          "name" => "Public set",
          "description" => "A set of songs",
          "images" => [ { "url" => "playlist.jpg", "width" => 300 } ],
          "external_urls" => { "spotify" => "https://playlist" },
          "items" => {
            "items" => [
              {
                "item" => {
                  "id" => "track-1",
                  "name" => "Playlist song",
                  "artists" => [ { "name" => "Artist" } ],
                  "album" => { "name" => "Album", "images" => [] },
                  "duration_ms" => 200_000,
                  "external_urls" => { "spotify" => "https://track" }
                }
              }
            ]
          }
        }
      end

      stubbing(Spotify::Client, :new, fake_client) do
        get tracks_api_playlist_path("public-1")
      end

      assert_response :success
      body = response.parsed_body
      assert_equal "Public set", body["playlist"]["name"]
      assert_equal "playlist.jpg", body["playlist"]["image_url"]
      assert_equal "Playlist song", body["tracks"].first["name"]
      assert_equal "Artist", body["tracks"].first["artists"]
    end

    test "reports when Spotify is not connected" do
      get api_playlists_path

      assert_response :service_unavailable
      assert_equal "No Spotify account linked yet", response.parsed_body["error"]
    end
  end
end
