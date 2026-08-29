require "test_helper"

module Api
  class TracksControllerTest < ActionDispatch::IntegrationTest
    def track(spotify_id, name: "Song", artist_names: "Artist")
      Track.create!(spotify_id: spotify_id, name: name, artist_names: artist_names)
    end

    test "without an API key configured, nothing new is searched" do
      track("trk1")

      calls = 0
      with_env("YOUTUBE_API_KEY" => nil) do
        stubbing_with(Youtube::ClipMatcher, :call, ->(_track) { calls += 1; "vid" }) do
          get api_track_youtube_matches_path, params: { ids: "trk1" }
        end
      end

      assert_response :success
      assert_equal 0, calls
      assert_empty response.parsed_body["matches"]
    end

    test "without an API key configured, an already-cached match is still served" do
      track("trk1")
      YoutubeMatch.create!(spotify_track_id: "trk1", video_id: "cached", matched_at: Time.current)

      with_env("YOUTUBE_API_KEY" => nil) do
        get api_track_youtube_matches_path, params: { ids: "trk1" }
      end

      assert_response :success
      assert_equal "https://www.youtube.com/watch?v=cached", response.parsed_body["matches"]["trk1"]
    end

    test "returns a url for a track a search finds a video for" do
      track("trk1")

      with_env("YOUTUBE_API_KEY" => "key") do
        stubbing(Youtube::ClipMatcher, :call, "abc123") do
          get api_track_youtube_matches_path, params: { ids: "trk1" }
        end
      end

      assert_response :success
      assert_equal "https://www.youtube.com/watch?v=abc123", response.parsed_body["matches"]["trk1"]
    end

    test "a track with no matching video is answered with null, not omitted" do
      track("trk1")

      with_env("YOUTUBE_API_KEY" => "key") do
        stubbing(Youtube::ClipMatcher, :call, nil) do
          get api_track_youtube_matches_path, params: { ids: "trk1" }
        end
      end

      assert_response :success
      matches = response.parsed_body["matches"]
      assert matches.key?("trk1"), "a resolved-but-not-found track must not read as unresolved"
      assert_nil matches["trk1"]
    end

    test "an id past the resolve cap is left out entirely, not answered with null" do
      ids = (1..Api::TracksController::MAX_RESOLVES + 1).map { |i| "trk#{i}" }
      ids.each { |id| track(id) }

      with_env("YOUTUBE_API_KEY" => "key") do
        stubbing(Youtube::ClipMatcher, :call, nil) do
          get api_track_youtube_matches_path, params: { ids: ids.join(",") }
        end
      end

      assert_response :success
      matches = response.parsed_body["matches"]
      assert_equal Api::TracksController::MAX_RESOLVES, matches.size
      refute matches.key?(ids.last), "an id the cap skipped must be retried later, not remembered as no-clip"
    end

    test "an id with no local track is skipped" do
      with_env("YOUTUBE_API_KEY" => "key") do
        get api_track_youtube_matches_path, params: { ids: "unknown" }
      end

      assert_response :success
      assert_empty response.parsed_body["matches"]
    end

    test "a fresh cached match is returned without spending a search" do
      track("trk1")
      YoutubeMatch.create!(spotify_track_id: "trk1", video_id: "cached", matched_at: Time.current)

      calls = 0
      with_env("YOUTUBE_API_KEY" => "key") do
        stubbing_with(Youtube::ClipMatcher, :call, ->(_track) { calls += 1; "new" }) do
          get api_track_youtube_matches_path, params: { ids: "trk1" }
        end
      end

      assert_response :success
      assert_equal 0, calls
      assert_equal "https://www.youtube.com/watch?v=cached", response.parsed_body["matches"]["trk1"]
    end

    # A page can carry many distinct tracks; only the first MAX_RESOLVES ever
    # ask never-before-seen track go to YouTube on one request — the rest
    # stay unresolved for a later ask, so one page load cannot burn a
    # meaningful slice of the day's quota.
    test "only resolves up to the cap of never-before-seen tracks per request" do
      ids = (1..Api::TracksController::MAX_RESOLVES + 3).map { |i| "trk#{i}" }
      ids.each { |id| track(id) }

      calls = 0
      with_env("YOUTUBE_API_KEY" => "key") do
        stubbing_with(Youtube::ClipMatcher, :call, ->(_track) { calls += 1; "vid" }) do
          get api_track_youtube_matches_path, params: { ids: ids.join(",") }
        end
      end

      assert_response :success
      assert_equal Api::TracksController::MAX_RESOLVES, calls
      assert_equal Api::TracksController::MAX_RESOLVES, response.parsed_body["matches"].size
    end

    test "lyrics: returns not-found for a track this app has never seen" do
      get api_track_lyrics_path("unknown")

      assert_response :success
      assert_equal({ "found" => false, "instrumental" => false, "plain_lyrics" => nil, "synced_lyrics" => nil },
                   response.parsed_body)
    end

    test "lyrics: resolves and returns a found track's lyrics" do
      track("trk1")

      stubbing(Lrclib::LyricsMatcher, :call, { "plainLyrics" => "la la la", "syncedLyrics" => "[00:01.00]la",
                                               "instrumental" => false }) do
        get api_track_lyrics_path("trk1")
      end

      assert_response :success
      body = response.parsed_body
      assert body["found"]
      assert_equal "la la la", body["plain_lyrics"]
      assert_equal "[00:01.00]la", body["synced_lyrics"]
    end

    test "lyrics: an instrumental track reads as found with no text" do
      track("trk1")

      stubbing(Lrclib::LyricsMatcher, :call, { "instrumental" => true }) do
        get api_track_lyrics_path("trk1")
      end

      assert_response :success
      body = response.parsed_body
      assert body["found"]
      assert body["instrumental"]
      assert_nil body["plain_lyrics"]
    end

    test "lyrics: a cached lookup is served without asking lrclib again" do
      track("trk1")
      Lyric.create!(spotify_track_id: "trk1", plain_lyrics: "cached", matched_at: Time.current)

      calls = 0
      stubbing_with(Lrclib::LyricsMatcher, :call, ->(_track) { calls += 1; {} }) do
        get api_track_lyrics_path("trk1")
      end

      assert_response :success
      assert_equal 0, calls
      assert_equal "cached", response.parsed_body["plain_lyrics"]
    end
  end
end
