require "test_helper"

module Api
  class TopItemsControllerTest < ActionDispatch::IntegrationTest
    test "returns the owner's top artists and tracks" do
      fake_client = Object.new
      fake_client.define_singleton_method(:top_items) do |type:, time_range: nil, limit: nil|
        case type
        when "artists"
          {
            "items" => [
              {
                "id" => "artist-1",
                "name" => "Artist",
                "images" => [ { "url" => "artist.jpg", "width" => 300 } ],
                "external_urls" => { "spotify" => "artist-url" }
              }
            ]
          }
        when "tracks"
          {
            "items" => [
              {
                "id" => "track-1",
                "name" => "Song",
                "artists" => [ { "id" => "artist-1", "name" => "Artist" } ],
                "album" => { "name" => "Album", "images" => [ { "url" => "album.jpg", "width" => 300 } ] },
                "duration_ms" => 200_000,
                "explicit" => false
              }
            ]
          }
        end
      end

      stubbing(Spotify::Client, :new, fake_client) do
        get api_top_items_path
      end

      assert_response :success
      body = response.parsed_body
      assert_equal "Artist", body["artists"].first["name"]
      assert_equal "artist.jpg", body["artists"].first["image_url"]
      assert_equal "Song", body["tracks"].first["name"]
      assert_equal "Album", body["tracks"].first["album"]
    end

    test "reports missing scope as forbidden" do
      fake_client = Object.new
      fake_client.define_singleton_method(:top_items) do |type:, time_range: nil, limit: nil|
        raise Spotify::Error.new("Spotify API returned 403", status: 403)
      end

      stubbing(Spotify::Client, :new, fake_client) do
        get api_top_items_path
      end

      assert_response :forbidden
      assert_match(/user-top-read/, response.parsed_body["error"])
    end

    test "reports when Spotify is not connected" do
      get api_top_items_path

      assert_response :service_unavailable
      assert_equal "No Spotify account linked yet", response.parsed_body["error"]
    end
  end
end
