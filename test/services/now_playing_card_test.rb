require "test_helper"

class NowPlayingCardTest < ActiveSupport::TestCase
  def account
    @account ||= SpotifyAccount.create!(owner: true, spotify_user_id: "owner")
  end

  def play(overrides = {})
    track = Track.create!({
      spotify_id: "trk1", name: "Song", artist_names: "Artist",
      duration_ms: 180_000, album_image_url: "https://cdn.example/cover.jpg"
    }.merge(overrides.delete(:track) || {}))

    Play.create!({ track: track, spotify_account: account, played_at: Time.current }.merge(overrides))
  end

  test "an empty feed renders a placeholder card, not a crash" do
    svg = NowPlayingCard.new(nil).to_svg

    assert_includes svg, "Nothing played yet"
    assert_includes svg, "<svg"
  end

  test "a track still within its own duration reads as playing now" do
    svg = NowPlayingCard.new(play(played_at: 30.seconds.ago)).to_svg

    assert_includes svg, "NOW PLAYING"
    assert_not_includes svg, "LAST PLAYED"
  end

  test "a track past its own duration reads as last played, with a relative time" do
    svg = NowPlayingCard.new(play(played_at: 10.minutes.ago)).to_svg

    assert_includes svg, "LAST PLAYED · 10m ago"
    assert_not_includes svg, "NOW PLAYING"
  end

  test "a track with no known duration is never treated as still playing" do
    svg = NowPlayingCard.new(play(played_at: 1.second.ago, track: { duration_ms: nil })).to_svg

    assert_includes svg, "LAST PLAYED"
  end

  test "track name and artist are XML-escaped" do
    svg = NowPlayingCard.new(play(track: { name: "Rock & Roll <3", artist_names: "AC/DC" })).to_svg

    assert_includes svg, "Rock &amp; Roll &lt;3"
    assert_not_includes svg, "Rock & Roll <3"
  end

  test "a long track or artist name is truncated in the visible text, not the a11y label" do
    long_name = "A" * 60
    svg = NowPlayingCard.new(play(track: { name: long_name })).to_svg

    # The full name stays in aria-label — screen readers benefit from it,
    # only the drawn glyphs need to fit inside the card.
    visible_text = svg[/<text[^>]*font-size="18"[^>]*>([^<]*)<\/text>/, 1]

    assert_not_equal long_name, visible_text
    assert_includes visible_text, "…"
    assert_includes svg, "aria-label=\"#{long_name} by Artist\""
  end

  test "without cover art, a placeholder note glyph is drawn instead of a broken image" do
    svg = NowPlayingCard.new(play(track: { album_image_url: nil })).to_svg

    assert_not_includes svg, "<image"
    assert_includes svg, NowPlayingCard::NOTE_PATH
  end

  test "with cover art, the real image is embedded by url" do
    svg = NowPlayingCard.new(play).to_svg

    assert_includes svg, "https://cdn.example/cover.jpg"
  end
end
