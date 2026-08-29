require "test_helper"

class BackfillYoutubeMatchesJobTest < ActiveJob::TestCase
  def account
    @account ||= SpotifyAccount.create!(owner: true, spotify_user_id: "owner")
  end

  def track_played_at(spotify_id, played_at)
    track = Track.create!(spotify_id: spotify_id, name: spotify_id, artist_names: "Artist")
    Play.create!(track: track, spotify_account: account, played_at: played_at)
    track
  end

  def resolving(replacement, &block)
    stubbing_with(Youtube::ClipMatcher, :call, ->(_track) { replacement.call }, &block)
  end

  test "does nothing without an API key configured" do
    track_played_at("trk1", 1.hour.ago)

    calls = 0
    with_env("YOUTUBE_API_KEY" => nil) do
      resolving(-> { calls += 1; "vid" }) { BackfillYoutubeMatchesJob.perform_now }
    end

    assert_equal 0, calls
    assert_equal 0, YoutubeMatch.count
  end

  test "resolves the most recently played unmatched track" do
    track_played_at("old", 2.hours.ago)
    recent = track_played_at("new", 1.minute.ago)

    resolved = nil
    with_env("YOUTUBE_API_KEY" => "key") do
      resolving(-> { "vid" }) { BackfillYoutubeMatchesJob.perform_now }
    end
    resolved = YoutubeMatch.sole

    assert_equal recent.spotify_id, resolved.spotify_track_id
  end

  test "skips a track that already has a fresh match" do
    track_played_at("trk1", 1.hour.ago)
    YoutubeMatch.create!(spotify_track_id: "trk1", video_id: "cached", matched_at: Time.current)

    calls = 0
    with_env("YOUTUBE_API_KEY" => "key") do
      resolving(-> { calls += 1; "vid" }) { BackfillYoutubeMatchesJob.perform_now }
    end

    assert_equal 0, calls
  end

  test "a stale match is worked out again" do
    track = track_played_at("trk1", 1.hour.ago)
    YoutubeMatch.create!(spotify_track_id: "trk1", video_id: "old",
                         matched_at: (YoutubeMatch::FRESH_FOR + 1.day).ago)

    with_env("YOUTUBE_API_KEY" => "key") do
      resolving(-> { "new" }) { BackfillYoutubeMatchesJob.perform_now }
    end

    assert_equal "new", YoutubeMatch.find_by!(spotify_track_id: track.spotify_id).video_id
  end

  test "only resolves BATCH_SIZE tracks in one run" do
    (BackfillYoutubeMatchesJob::BATCH_SIZE + 3).times { |i| track_played_at("trk#{i}", i.hours.ago) }

    calls = 0
    with_env("YOUTUBE_API_KEY" => "key") do
      resolving(-> { calls += 1; "vid" }) { BackfillYoutubeMatchesJob.perform_now }
    end

    assert_equal BackfillYoutubeMatchesJob::BATCH_SIZE, calls
  end
end
