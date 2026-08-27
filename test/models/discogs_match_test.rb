require "test_helper"

class DiscogsMatchTest < ActiveSupport::TestCase
  def release = { "discogs_id" => 7, "title" => "Silence", "artist" => "From Ashes Rise" }

  def result(playable: 11)
    { "album" => { "spotify_id" => "alb", "spotify_url" => "https://album" },
      "track_count" => 11, "playable_count" => playable, "tracks" => [] }
  end

  def matching(replacement, &block)
    stubbing_with(Spotify::ReleaseMatcher, :call, ->(_release) { replacement.call }, &block)
  end

  test "a match older than the freshness window is worked out again" do
    stale = DiscogsMatch.create!(discogs_id: 7, spotify_album_id: "old", track_count: 11,
                                 playable_count: 0, payload: result(playable: 0),
                                 matched_at: (DiscogsMatch::FRESH_FOR + 1.day).ago)

    calls = 0
    matching(-> { calls += 1; result }) { DiscogsMatch.resolve(release) }

    assert_equal 1, calls
    assert_equal 11, stale.reload.playable_count
    assert_equal "alb", stale.spotify_album_id
  end

  test "a row without a payload is not treated as an answer" do
    DiscogsMatch.create!(discogs_id: 7, matched_at: Time.current)

    calls = 0
    matching(-> { calls += 1; result }) { DiscogsMatch.resolve(release) }

    assert_equal 1, calls
  end

  test "summary says matched only when an album was found" do
    match = DiscogsMatch.create!(discogs_id: 7, track_count: 11, playable_count: 0)

    assert_equal false, match.summary[:matched]
    assert_equal 0, match.summary[:playable_count]
  end
end
