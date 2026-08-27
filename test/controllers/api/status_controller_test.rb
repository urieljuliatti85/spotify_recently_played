require "test_helper"

module Api
  class StatusControllerTest < ActionDispatch::IntegrationTest
    test "reports nothing linked on a fresh install" do
      get api_status_path
      body = response.parsed_body

      assert_response :success
      assert_equal false, body["connected"]
      assert_empty body["listeners"]
    end

    test "lists the listeners with the owner first and a play count each" do
      owner = SpotifyAccount.create!(display_name: "Owner", spotify_user_id: "o", owner: true, refresh_token: "r")
      friend = SpotifyAccount.create!(display_name: "Ana", spotify_user_id: "a", refresh_token: "r")
      track = Track.create!(spotify_id: "t", name: "Song")
      Play.create!(spotify_account: owner, track: track, played_at: 1.hour.ago.round)
      Play.create!(spotify_account: owner, track: track, played_at: 2.hours.ago.round)
      Play.create!(spotify_account: friend, track: track, played_at: 3.hours.ago.round)

      get api_status_path
      listeners = response.parsed_body["listeners"]

      assert_equal true, response.parsed_body["connected"]
      assert_equal [ "Owner", "Ana" ], listeners.map { |l| l["name"] }
      assert_equal [ 2, 1 ], listeners.map { |l| l["plays_count"] }
      assert_equal [ true, false ], listeners.map { |l| l["owner"] }
      assert_equal "https://open.spotify.com/user/o", listeners.first["spotify_url"]
    end

    test "a hidden listener is not advertised" do
      SpotifyAccount.create!(display_name: "Shy", spotify_user_id: "s", visible: false, refresh_token: "r")

      get api_status_path

      assert_equal true, response.parsed_body["connected"], "still linked, just not shown"
      assert_empty response.parsed_body["listeners"]
    end

    test "tells the frontend whether the caller may use the owner-only actions" do
      get api_status_path
      assert_response :success
      assert_equal false, response.parsed_body["admin"]

      get api_status_path, headers: admin_headers
      assert_response :success
      assert_equal true, response.parsed_body["admin"]
    end
  end
end
