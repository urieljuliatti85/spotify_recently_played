require "test_helper"

module Api
  class PlaysControllerTest < ActionDispatch::IntegrationTest
    setup do
      @owner = SpotifyAccount.create!(display_name: "Owner", spotify_user_id: "owner", owner: true)
      @track = Track.create!(spotify_id: "t1", name: "Song", artist_names: "Artist")
      @plays = 3.times.map do |i|
        Play.create!(spotify_account: @owner, track: @track, played_at: (i + 1).hours.ago.round)
      end
    end

    test "returns plays newest first" do
      get api_plays_path
      body = response.parsed_body

      assert_response :success
      assert_equal @plays.map(&:id), body["plays"].map { |p| p["id"] }
      assert_equal "Song", body["plays"].first.dig("track", "name")
    end

    test "paginates with the returned cursor" do
      get api_plays_path, params: { limit: 2 }
      first_page = response.parsed_body
      assert_equal 2, first_page["plays"].size

      get api_plays_path, params: { limit: 2, before: first_page["next_cursor"] }
      second_page = response.parsed_body

      assert_equal [ @plays.last.id ], second_page["plays"].map { |p| p["id"] }
      assert_nil second_page["next_cursor"]
    end

    test "clamps an absurd limit" do
      get api_plays_path, params: { limit: 10_000 }
      assert_response :success
      assert_equal 3, response.parsed_body["plays"].size
    end

    test "ignores an unparseable cursor rather than failing" do
      get api_plays_path, params: { before: "not-a-timestamp" }

      assert_response :success
      assert_equal 3, response.parsed_body["plays"].size
    end

    test "serializes the credits as addressable artists, in order" do
      track = Track.upsert_from_spotify!(
        "id" => "t2", "name" => "Duet", "album" => { "name" => "Split", "images" => [] },
        "artists" => [
          { "id" => "a1", "name" => "Tyler, The Creator" },
          { "id" => "a2", "name" => "Second", "external_urls" => { "spotify" => "https://artist" } }
        ]
      )
      Play.create!(spotify_account: @owner, track: track, played_at: 1.minute.ago.round)

      get api_plays_path
      credits = response.parsed_body["plays"].first.dig("track", "artist_list")

      assert_equal [ "a1", "a2" ], credits.map { |a| a["id"] }
      assert_equal [ "Tyler, The Creator", "Second" ], credits.map { |a| a["name"] }
      assert_equal "https://artist", credits.last["url"]
    end

    test "the feed mixes listeners and names who played each track" do
      friend = SpotifyAccount.create!(display_name: "Friend", spotify_user_id: "friend", avatar_url: "face.jpg")
      Play.create!(spotify_account: friend, track: @track, played_at: 1.minute.ago.round)

      get api_plays_path
      body = response.parsed_body["plays"]

      assert_equal [ "Friend", "Owner", "Owner", "Owner" ], body.map { |p| p.dig("listener", "name") }
      assert_equal "face.jpg", body.first.dig("listener", "avatar_url")
      assert_equal false, body.first.dig("listener", "owner")
      assert_equal true, body.last.dig("listener", "owner")
    end

    test "the listener filter narrows the feed to one person" do
      friend = SpotifyAccount.create!(display_name: "Friend", spotify_user_id: "friend")
      Play.create!(spotify_account: friend, track: @track, played_at: 1.minute.ago.round)

      get api_plays_path, params: { listener: friend.id }
      body = response.parsed_body["plays"]

      assert_equal 1, body.size
      assert_equal "Friend", body.first.dig("listener", "name")
    end

    test "a hidden listener is left off the public feed entirely" do
      hidden = SpotifyAccount.create!(display_name: "Shy", spotify_user_id: "shy", visible: false)
      Play.create!(spotify_account: hidden, track: @track, played_at: 1.minute.ago.round)

      get api_plays_path
      assert_equal [ "Owner" ], response.parsed_body["plays"].map { |p| p.dig("listener", "name") }.uniq

      # ...and cannot be pulled back in by naming them directly.
      get api_plays_path, params: { listener: hidden.id }
      assert_empty response.parsed_body["plays"]
    end

    test "two listeners can play at the same instant" do
      friend = SpotifyAccount.create!(display_name: "Friend", spotify_user_id: "friend")
      instant = 1.minute.ago.round

      Play.create!(spotify_account: @owner, track: @track, played_at: instant)
      assert_nothing_raised do
        Play.create!(spotify_account: friend, track: @track, played_at: instant)
      end
    end

    test "a track with no linked artists serializes an empty credit list" do
      get api_plays_path
      track = response.parsed_body["plays"].first["track"]

      assert_equal [], track["artist_list"]
      assert_equal "Artist", track["artists"], "the display string still stands in"
    end
  end
end
