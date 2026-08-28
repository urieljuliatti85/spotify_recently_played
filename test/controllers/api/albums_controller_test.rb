require "test_helper"

module Api
  class AlbumsControllerTest < ActionDispatch::IntegrationTest
    test "returns tracks from Spotify for an album" do
      fake_client = Object.new
      fake_client.define_singleton_method(:me) { { "country" => "BR" } }
      # /v1/albums/{id}'s own shape: tracks nested under tracks.items, as
      # "simplified" track objects that do not repeat the album's own
      # name/id/images (they don't need to — the payload already carries it).
      fake_client.define_singleton_method(:album) do |_id, market: nil|
        {
          "id" => "album-1",
          "name" => "New album",
          "images" => [ { "url" => "cover.jpg", "width" => 300 } ],
          "tracks" => {
            "items" => [
              {
                "id" => "track-1",
                "name" => "New song",
                "artists" => [ { "id" => "artist-1", "name" => "Artist" } ],
                "external_urls" => { "spotify" => "track-url" },
                "duration_ms" => 180_000,
                "explicit" => false
              }
            ]
          }
        }
      end

      stubbing(Spotify::Client, :new, fake_client) do
        get api_album_tracks_path("album-1")
      end

      assert_response :success
      track = response.parsed_body["tracks"].first
      assert_equal "New song", track["name"]
      assert_equal "New album", track["album"]
      assert_equal "album-1", track["album_spotify_id"]
      assert_equal "cover.jpg", track["album_image_url"]
    end

    test "reports when Spotify is not connected" do
      get api_album_tracks_path("album-1")

      assert_response :service_unavailable
      assert_equal "No Spotify account linked yet", response.parsed_body["error"]
    end

    test "returns matching album releases from the Discogs Shelf" do
      shelf = Object.new
      shelf.define_singleton_method(:album_releases) do |_title, _artist|
        [
          { "discogs_id" => 42, "title" => "Album", "artist" => "Artist" }
        ]
      end

      stubbing(DiscogsShelf::Client, :new, shelf) do
        get api_album_releases_path, params: { title: "Album", artist: "Artist" }
      end

      assert_response :success
      assert_equal 42, response.parsed_body["releases"].sole["discogs_id"]
    end

    test "matches a release Discogs spells with a subtitle Spotify omits" do
      shelf = stub_shelf("discogs_id" => 42, "title" => "Unleashed In The East (Live In Japan)", "artist" => "Judas Priest")

      stubbing(DiscogsShelf::Client, :new, shelf) do
        get api_album_releases_path, params: { title: "Unleashed In The East", artist: "Judas Priest" }
      end

      assert_response :success
      assert_equal 42, response.parsed_body["releases"].sole["discogs_id"]
    end

    test "matches a release when Spotify hangs an edition off the title" do
      shelf = stub_shelf("discogs_id" => 42, "title" => "Feel The Darkness", "artist" => "Poison Idea")

      stubbing(DiscogsShelf::Client, :new, shelf) do
        get api_album_releases_path, params: { title: "Feel the Darkness - 2018 Remaster", artist: "Poison Idea" }
      end

      assert_response :success
      assert_equal 42, response.parsed_body["releases"].sole["discogs_id"]
    end

    test "does not collapse two records onto each other over a plain dash" do
      shelf = stub_shelf("discogs_id" => 42, "title" => "Three - Architects Of Troubled Sleep", "artist" => "Cursed")

      stubbing(DiscogsShelf::Client, :new, shelf) do
        get api_album_releases_path, params: { title: "One", artist: "Cursed" }
      end

      assert_response :success
      assert_empty response.parsed_body["releases"]
    end

    test "matches a release when Spotify has additional album artists" do
      shelf = Object.new
      shelf.define_singleton_method(:album_releases) do |_title, _artist|
        [
          { "discogs_id" => 42, "title" => "Album", "artist" => "Artist" }
        ]
      end

      stubbing(DiscogsShelf::Client, :new, shelf) do
        get api_album_releases_path, params: { title: "Album", artist: "Artist, Guest Artist" }
      end

      assert_response :success
      assert_equal 42, response.parsed_body["releases"].sole["discogs_id"]
    end

    private

    def stub_shelf(*releases)
      Object.new.tap do |shelf|
        shelf.define_singleton_method(:album_releases) { |_title, _artist| releases }
      end
    end
  end
end
