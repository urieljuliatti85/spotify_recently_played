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
              "images" => [{ "url" => "playlist.jpg", "width" => 300 }],
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

    test "returns playable playlist tracks" do
      fake_client = Object.new
      fake_client.define_singleton_method(:playlist_tracks) do |_id|
        {
          "items" => [
            {
              "item" => {
                "id" => "track-1",
                "name" => "Playlist song",
                "artists" => [{ "name" => "Artist" }],
                "album" => { "name" => "Album", "images" => [] },
                "duration_ms" => 200_000,
                "external_urls" => { "spotify" => "https://track" }
              }
            }
          ]
        }
      end

      stubbing(Spotify::Client, :new, fake_client) do
        get tracks_api_playlist_path("public-1")
      end

      assert_response :success
      assert_equal "Playlist song", response.parsed_body["tracks"].first["name"]
      assert_equal "Artist", response.parsed_body["tracks"].first["artists"]
    end

    test "reports when Spotify is not connected" do
      get api_playlists_path

      assert_response :service_unavailable
      assert_equal "No Spotify account linked yet", response.parsed_body["error"]
    end
  end
end
