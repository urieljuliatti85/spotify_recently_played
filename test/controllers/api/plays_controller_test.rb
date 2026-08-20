require "test_helper"

module Api
  class PlaysControllerTest < ActionDispatch::IntegrationTest
    setup do
      @track = Track.create!(spotify_id: "t1", name: "Song", artist_names: "Artist")
      @plays = 3.times.map { |i| Play.create!(track: @track, played_at: (i + 1).hours.ago.round) }
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
  end
end
