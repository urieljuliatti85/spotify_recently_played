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

  test "a fresh match is returned as-is, without asking Spotify again" do
    fresh = DiscogsMatch.create!(discogs_id: 7, spotify_album_id: "alb", track_count: 11,
                                 playable_count: 11, payload: result, matched_at: Time.current)

    calls = 0
    match = nil
    matching(-> { calls += 1; result }) { match = DiscogsMatch.resolve(release) }

    assert_equal 0, calls, "the whole point of caching a match is to skip the search when it is still good"
    assert_equal fresh.id, match.id
  end

  test "force: true recomputes even a match that is still fresh" do
    DiscogsMatch.create!(discogs_id: 7, spotify_album_id: "old", track_count: 11,
                         playable_count: 0, payload: result(playable: 0), matched_at: Time.current)

    calls = 0
    matching(-> { calls += 1; result }) { DiscogsMatch.resolve(release, force: true) }

    assert_equal 1, calls
  end

  # Two visitors can open the same never-before-seen release at once: both see
  # no row, both build one, and the database's unique index — not the app-level
  # validation, which only catches a row already committed by the time it
  # queries — is what actually decides who loses a true race. A single test
  # process can't race itself, so the loss is forced directly at the point
  # `store!` would hit that index.
  test "the loser of a race to insert the same release hands back the winner's row" do
    winner = DiscogsMatch.create!(discogs_id: 7, spotify_album_id: "theirs", track_count: 11,
                                  playable_count: 5, matched_at: Time.current)
    original_store = DiscogsMatch.instance_method(:store!)
    DiscogsMatch.define_method(:store!) { |*| raise ActiveRecord::RecordNotUnique, "duplicate discogs_id" }

    begin
      match = matching(-> { result }) { DiscogsMatch.resolve(release) }
    ensure
      DiscogsMatch.define_method(:store!, original_store)
    end

    assert_equal winner.id, match.id
    assert_equal "theirs", match.spotify_album_id
  end

  test "summary says matched only when an album was found" do
    match = DiscogsMatch.create!(discogs_id: 7, track_count: 11, playable_count: 0)

    assert_equal false, match.summary[:matched]
    assert_equal 0, match.summary[:playable_count]
  end
end
