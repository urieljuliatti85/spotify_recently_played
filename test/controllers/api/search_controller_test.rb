require "test_helper"

module Api
  class SearchControllerTest < ActionDispatch::IntegrationTest
    def fake_client
      client = Object.new
      client.define_singleton_method(:search) do |query, type:, limit:, market:|
        @search_call = { query: query, type: type, limit: limit, market: market }
        {
          "tracks" => { "items" => [
            {
              "id" => "track-1",
              "name" => "Found song",
              "artists" => [ { "id" => "artist-1", "name" => "Found artist" } ],
              "album" => { "id" => "album-1", "name" => "Found album",
                           "images" => [ { "url" => "cover.jpg", "width" => 300 } ] },
              "external_urls" => { "spotify" => "track-url" },
              "duration_ms" => 180_000,
              "explicit" => false
            }
          ] },
          "albums" => { "items" => [
            {
              "id" => "album-2",
              "name" => "Found LP",
              "artists" => [ { "name" => "Found artist" } ],
              "images" => [ { "url" => "album-cover.jpg", "width" => 300 } ],
              "external_urls" => { "spotify" => "album-url" }
            }
          ] }
        }
      end
      client.define_singleton_method(:search_call) { @search_call }
      client.define_singleton_method(:me) { { "country" => "BR" } }
      client
    end

    test "returns catalogue tracks and albums for a query" do
      client = fake_client

      stubbing(Spotify::Client, :new, client) do
        get api_search_path, params: { q: "found" }
      end

      assert_response :success
      track = response.parsed_body["tracks"].sole
      assert_equal "Found song", track["name"]
      assert_equal "Found artist", track["artists"]
      assert_equal "album-1", track["album_spotify_id"]

      album = response.parsed_body["albums"].sole
      assert_equal "Found LP", album["name"]
      assert_equal "album-2", album["spotify_id"]
      assert_equal "album-cover.jpg", album["image_url"]

      assert_equal "track,album", client.search_call[:type]
    end

    test "answers empty results for a blank query without touching Spotify" do
      get api_search_path, params: { q: "  " }

      assert_response :success
      assert_equal({ "tracks" => [], "albums" => [] }, response.parsed_body)
    end

    test "reports when Spotify is not connected" do
      get api_search_path, params: { q: "found" }

      assert_response :service_unavailable
    end
  end
end
