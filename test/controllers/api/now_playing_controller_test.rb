require "test_helper"

module Api
  class NowPlayingControllerTest < ActionDispatch::IntegrationTest
    def account(overrides = {})
      SpotifyAccount.create!({ owner: true, spotify_user_id: "owner" }.merge(overrides))
    end

    def track(overrides = {})
      Track.create!({ spotify_id: "trk1", name: "Song", artist_names: "Artist" }.merge(overrides))
    end

    test "renders an SVG with the right content type" do
      Play.create!(track: track, spotify_account: account, played_at: Time.current)

      get api_now_playing_svg_path

      assert_response :success
      assert_equal "image/svg+xml", response.media_type
      assert_includes response.body, "Song"
    end

    test "renders the placeholder card when nobody has ever played anything" do
      get api_now_playing_svg_path

      assert_response :success
      assert_includes response.body, "Nothing played yet"
    end

    test "a hidden listener's play does not show up, same as the public feed" do
      hidden = account(visible: false, spotify_user_id: "hidden")
      Play.create!(track: track, spotify_account: hidden, played_at: Time.current)

      get api_now_playing_svg_path

      assert_response :success
      assert_includes response.body, "Nothing played yet"
    end

    test "?listener= scopes the badge to one person, like the feed's own filter" do
      owner = account
      friend = account(spotify_user_id: "friend", display_name: "Friend")
      Play.create!(track: track(spotify_id: "owner-trk", name: "Owner Song"), spotify_account: owner,
                   played_at: 2.hours.ago)
      Play.create!(track: track(spotify_id: "friend-trk", name: "Friend Song"), spotify_account: friend,
                   played_at: 1.minute.ago)

      get api_now_playing_svg_path, params: { listener: owner.id }

      assert_response :success
      assert_includes response.body, "Owner Song"
      assert_not_includes response.body, "Friend Song"
    end
  end
end
