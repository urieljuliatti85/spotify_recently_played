require "test_helper"

class YoutubeMatchTest < ActiveSupport::TestCase
  def track
    Track.create!(spotify_id: "trk1", name: "Song", artist_names: "Artist")
  end

  def matching(replacement, &block)
    stubbing_with(Youtube::ClipMatcher, :call, ->(_track) { replacement.call }, &block)
  end

  test "a match older than the freshness window is worked out again" do
    stale = YoutubeMatch.create!(spotify_track_id: "trk1", video_id: "old",
                                 matched_at: (YoutubeMatch::FRESH_FOR + 1.day).ago)

    calls = 0
    matching(-> { calls += 1; "new" }) { YoutubeMatch.resolve(track) }

    assert_equal 1, calls
    assert_equal "new", stale.reload.video_id
  end

  test "a fresh match is returned as-is, without asking YouTube again" do
    fresh = YoutubeMatch.create!(spotify_track_id: "trk1", video_id: "vid", matched_at: Time.current)

    calls = 0
    match = nil
    matching(-> { calls += 1; "vid" }) { match = YoutubeMatch.resolve(track) }

    assert_equal 0, calls, "the whole point of caching a match is to skip the search when it is still good"
    assert_equal fresh.id, match.id
  end

  test "a fresh row with no video is still treated as an answer, not retried" do
    YoutubeMatch.create!(spotify_track_id: "trk1", video_id: nil, matched_at: Time.current)

    calls = 0
    matching(-> { calls += 1; "vid" }) { YoutubeMatch.resolve(track) }

    assert_equal 0, calls
  end

  # Two visitors can ask about the same never-before-seen track at once: both
  # see no row, both build one, and the database's unique index is what
  # actually decides who loses the race.
  test "the loser of a race to insert the same track hands back the winner's row" do
    winner = YoutubeMatch.create!(spotify_track_id: "trk1", video_id: "theirs", matched_at: Time.current)
    original_store = YoutubeMatch.instance_method(:store!)
    YoutubeMatch.define_method(:store!) { |*| raise ActiveRecord::RecordNotUnique, "duplicate spotify_track_id" }

    begin
      match = matching(-> { "vid" }) { YoutubeMatch.resolve(track) }
    ensure
      YoutubeMatch.define_method(:store!, original_store)
    end

    assert_equal winner.id, match.id
    assert_equal "theirs", match.video_id
  end

  test "video_url is nil without a video id" do
    match = YoutubeMatch.create!(spotify_track_id: "trk1")

    assert_nil match.video_url
  end

  test "video_url points at the watch page" do
    match = YoutubeMatch.create!(spotify_track_id: "trk1", video_id: "abc")

    assert_equal "https://www.youtube.com/watch?v=abc", match.video_url
  end
end
