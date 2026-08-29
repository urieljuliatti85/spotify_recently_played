require "test_helper"

class LyricTest < ActiveSupport::TestCase
  def track
    Track.create!(spotify_id: "trk1", name: "Song", artist_names: "Artist")
  end

  def matching(replacement, &block)
    stubbing_with(Lrclib::LyricsMatcher, :call, ->(_track) { replacement.call }, &block)
  end

  test "a match older than the freshness window is worked out again" do
    stale = Lyric.create!(spotify_track_id: "trk1", plain_lyrics: "old",
                          matched_at: (Lyric::FRESH_FOR + 1.day).ago)

    calls = 0
    matching(-> { calls += 1; { "plainLyrics" => "new" } }) { Lyric.resolve(track) }

    assert_equal 1, calls
    assert_equal "new", stale.reload.plain_lyrics
  end

  test "a fresh match is returned as-is, without asking lrclib again" do
    fresh = Lyric.create!(spotify_track_id: "trk1", plain_lyrics: "la", matched_at: Time.current)

    calls = 0
    match = nil
    matching(-> { calls += 1; { "plainLyrics" => "la" } }) { match = Lyric.resolve(track) }

    assert_equal 0, calls, "the whole point of caching a lookup is to skip it when still good"
    assert_equal fresh.id, match.id
  end

  test "a nil result (nothing found) stores as not found, not retried while fresh" do
    Lyric.create!(spotify_track_id: "trk1", matched_at: Time.current)

    calls = 0
    matching(-> { calls += 1; { "plainLyrics" => "la" } }) { Lyric.resolve(track) }

    assert_equal 0, calls
  end

  test "the loser of a race to insert the same track hands back the winner's row" do
    winner = Lyric.create!(spotify_track_id: "trk1", plain_lyrics: "theirs", matched_at: Time.current)
    original_store = Lyric.instance_method(:store!)
    Lyric.define_method(:store!) { |*| raise ActiveRecord::RecordNotUnique, "duplicate spotify_track_id" }

    begin
      match = matching(-> { { "plainLyrics" => "mine" } }) { Lyric.resolve(track) }
    ensure
      Lyric.define_method(:store!, original_store)
    end

    assert_equal winner.id, match.id
    assert_equal "theirs", match.plain_lyrics
  end

  test "found? is true for plain lyrics" do
    assert Lyric.new(plain_lyrics: "la la").found?
  end

  test "found? is true for an instrumental with no text" do
    assert Lyric.new(instrumental: true).found?
  end

  test "found? is false when nothing came back" do
    refute Lyric.new.found?
  end

  test "store! treats a nil result the same as an empty one" do
    lyric = Lyric.create!(spotify_track_id: "trk1")
    lyric.store!(nil)

    assert_nil lyric.plain_lyrics
    assert_not lyric.found?
  end
end
