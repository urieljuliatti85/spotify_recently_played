require "test_helper"

module Api
  class FollowedArtistsControllerTest < ActionDispatch::IntegrationTest
    test "returns the owner's followed artists" do
      fake_client = Object.new
      fake_client.define_singleton_method(:followed_artists) do
        {
          "artists" => {
            "items" => [
              {
                "id" => "artist-1",
                "name" => "Artist",
                "images" => [ { "url" => "artist.jpg", "width" => 300 } ],
                "external_urls" => { "spotify" => "artist-url" },
                "followers" => { "total" => 1234 }
              },
              { "id" => "", "name" => "Missing id" }
            ]
          }
        }
      end

      stubbing(Spotify::Client, :new, fake_client) do
        get api_followed_artists_path
      end

      assert_response :success
      artists = response.parsed_body["artists"]
      assert_equal 1, artists.length
      assert_equal "Artist", artists.first["name"]
      assert_equal "artist.jpg", artists.first["image_url"]
      assert_equal 1234, artists.first["followers"]
    end

    test "reports missing scope as forbidden" do
      fake_client = Object.new
      fake_client.define_singleton_method(:followed_artists) do
        raise Spotify::Error.new("Spotify API returned 403", status: 403)
      end

      stubbing(Spotify::Client, :new, fake_client) do
        get api_followed_artists_path
      end

      assert_response :forbidden
      assert_match(/user-follow-read/, response.parsed_body["error"])
    end

    test "reports when Spotify is not connected" do
      get api_followed_artists_path

      assert_response :service_unavailable
      assert_equal "No Spotify account linked yet", response.parsed_body["error"]
    end
  end
end
