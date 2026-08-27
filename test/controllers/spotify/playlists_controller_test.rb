require "test_helper"

module Spotify
  class PlaylistsControllerTest < ActionDispatch::IntegrationTest
    # Records what it was told to create and fill, so the two calls the feature
    # rests on can be asserted without reaching Spotify.
    class FakeClient
      attr_reader :created, :added

      def initialize(fail_with: nil)
        @fail_with = fail_with
        @added = []
      end

      def create_playlist(name:, description: nil)
        raise @fail_with if @fail_with

        @created = { name: name, description: description }
        { "id" => "new-1", "name" => name, "external_urls" => { "spotify" => "https://playlist" } }
      end

      def add_playlist_items(playlist_id, uris)
        @added << [ playlist_id, uris ]
      end

      def me
        { "country" => "BR" }
      end

      def search(query, type:, limit:, market:)
        @search_call = { query: query, type: type, limit: limit, market: market }
        { "tracks" => { "items" => [
          { "id" => format("%022d", 3), "name" => "Found track",
            "artists" => [ { "name" => "Found artist" } ], "album" => { "name" => "Found album" } }
        ] } }
      end

      attr_reader :search_call
    end

    def owner
      @owner ||= SpotifyAccount.create!(spotify_user_id: "owner-1", owner: true, refresh_token: "r")
    end

    def id_of(n) = format("%022d", n)

    test "the playlist routes are closed without the admin password" do
      get spotify_unheard_playlist_tracks_path
      assert_response :unauthorized

      post spotify_playlists_path, params: { name: "x", track_ids: [ id_of(1) ] }
      assert_response :unauthorized
    end

    test "a cross-site post is rejected even with the owner's credentials" do
      post spotify_playlists_path,
           params: { name: "x", track_ids: [ id_of(1) ] },
           headers: admin_headers.merge("HTTP_SEC_FETCH_SITE" => "cross-site")

      assert_response :forbidden
    end

    test "lists what the feed has never played" do
      stubbing(UnheardTracks, :call, [ { spotify_id: id_of(1), name: "Nocturnal Will" } ]) do
        get spotify_unheard_playlist_tracks_path, headers: admin_headers
      end

      assert_response :success
      assert_equal "Nocturnal Will", response.parsed_body["tracks"].sole["name"]
    end

    test "searches Spotify tracks for the playlist composer" do
      owner
      client = FakeClient.new

      stubbing(Client, :new, client) do
        get spotify_search_playlist_tracks_path, params: { q: "Found artist" }, headers: admin_headers
      end

      assert_response :success
      assert_equal "Found track", response.parsed_body["tracks"].sole["name"]
      assert_equal "Found artist", client.search_call[:query]
      assert_equal "track", client.search_call[:type]
    end

    test "creates a public playlist and fills it with the chosen tracks" do
      owner
      client = FakeClient.new

      stubbing(Client, :new, client) do
        post spotify_playlists_path,
             params: { name: "  Never played  ", track_ids: [ id_of(1), id_of(2) ] },
             headers: admin_headers.merge("HTTP_SEC_FETCH_SITE" => "same-origin")
      end

      assert_response :created
      assert_equal "Never played", client.created[:name]
      assert_equal [ [ "new-1", [ "spotify:track:#{id_of(1)}", "spotify:track:#{id_of(2)}" ] ] ], client.added
      assert_equal 2, response.parsed_body.dig("playlist", "tracks_count")
      assert_equal "https://playlist", response.parsed_body.dig("playlist", "spotify_url")
    end

    test "drops anything that is not a Spotify track id before building a uri" do
      owner
      client = FakeClient.new

      stubbing(Client, :new, client) do
        post spotify_playlists_path,
             params: { name: "Never played", track_ids: [ id_of(1), "../../evil", "short" ] },
             headers: admin_headers
      end

      assert_response :created
      assert_equal [ "spotify:track:#{id_of(1)}" ], client.added.sole.last
    end

    test "refuses a playlist with no name and one with nothing in it" do
      owner

      post spotify_playlists_path, params: { name: " ", track_ids: [ id_of(1) ] }, headers: admin_headers
      assert_response :unprocessable_entity

      post spotify_playlists_path, params: { name: "Never played", track_ids: [ "nope" ] }, headers: admin_headers
      assert_response :unprocessable_entity
    end

    test "a 403 from Spotify says which scope is missing rather than the status" do
      owner
      client = FakeClient.new(fail_with: Error.new("Spotify API returned 403", status: 403))

      stubbing(Client, :new, client) do
        post spotify_playlists_path,
             params: { name: "Never played", track_ids: [ id_of(1) ] },
             headers: admin_headers
      end

      assert_response :bad_gateway
      assert_includes response.parsed_body["error"], "playlist-modify-public"
    end

    test "says so when no account is linked yet" do
      post spotify_playlists_path, params: { name: "x", track_ids: [ id_of(1) ] }, headers: admin_headers

      assert_response :precondition_required
    end
  end
end
