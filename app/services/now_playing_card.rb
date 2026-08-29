require "cgi"

# Renders the public "now playing" badge as a self-contained SVG — meant to
# be hotlinked (`<img src=".../api/now_playing.svg">`), the same shape as the
# GitHub-profile Spotify widgets this mirrors.
#
# There is no live "currently playing" endpoint behind this: it reads the
# same locally-synced history the feed itself shows, and "now playing" is a
# heuristic — has the most recent play's track run its own duration yet?
# — over that last synced play, not a fresh call to Spotify. A viral README
# embed can't spend anyone's Spotify quota.
class NowPlayingCard
  WIDTH = 400
  HEIGHT = 120
  # Spotify's own green — recognizable at a glance as what this badge is
  # about, distinct from this app's own red accent used everywhere else.
  ACCENT = "#1db954"
  MUTED = "#64788e"

  NOTE_PATH = "M20 3v12.2a3.4 3.4 0 11-2-3.1V7.4l-8 1.9v8.9a3.4 3.4 0 11-2-3.1V6.6z"

  def initialize(play)
    @play = play
  end

  def to_svg
    play ? track_svg : empty_svg
  end

  private

  attr_reader :play

  def track_svg
    track = play.track

    <<~SVG
      <svg width="#{WIDTH}" height="#{HEIGHT}" viewBox="0 0 #{WIDTH} #{HEIGHT}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="#{esc("#{track.name} by #{track.artist_names}")}">
        #{background}
        #{art(track)}
        #{status_line}
        #{text(118, 62, track.name, size: 18, weight: 700, fill: "#f4f7fa", max: 26)}
        #{text(118, 86, track.artist_names, size: 14, weight: 400, fill: "#93a7bb", max: 32)}
      </svg>
    SVG
  end

  def empty_svg
    <<~SVG
      <svg width="#{WIDTH}" height="#{HEIGHT}" viewBox="0 0 #{WIDTH} #{HEIGHT}" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Nothing played yet">
        #{background}
        #{text(20, 66, "Nothing played yet", size: 15, weight: 600, fill: MUTED, max: 40)}
      </svg>
    SVG
  end

  def background
    <<~SVG
      <rect width="#{WIDTH}" height="#{HEIGHT}" rx="14" fill="#0b0d12"/>
      <rect x="0.5" y="0.5" width="#{WIDTH - 1}" height="#{HEIGHT - 1}" rx="13.5" fill="none" stroke="#1c2634"/>
    SVG
  end

  def art(track)
    return placeholder_art if track.album_image_url.blank?

    <<~SVG
      <clipPath id="art"><rect x="16" y="16" width="88" height="88" rx="10"/></clipPath>
      <image href="#{esc(track.album_image_url)}" x="16" y="16" width="88" height="88" preserveAspectRatio="xMidYMid slice" clip-path="url(#art)"/>
    SVG
  end

  # The same note glyph the app's own sidebar nav uses — one glyph language
  # across Ruby and JS, rather than inventing a second "no cover" icon.
  def placeholder_art
    <<~SVG
      <rect x="16" y="16" width="88" height="88" rx="10" fill="#111823"/>
      <path d="#{NOTE_PATH}" fill="#{MUTED}" transform="translate(28.8 28.8) scale(2.6)"/>
    SVG
  end

  def status_line
    if playing_now?
      "#{equalizer}#{text(138, 34, 'NOW PLAYING', size: 11, weight: 700, fill: ACCENT, max: 30, spacing: 1)}"
    else
      text(118, 34, "LAST PLAYED · #{relative_time}", size: 11, weight: 700, fill: MUTED, max: 30, spacing: 1)
    end
  end

  # Three bars animating their own height/position — a static image still
  # reads as "alive" without any script, since it's plain SVG <animate>.
  def equalizer
    <<~SVG
      <g transform="translate(118, 22)" fill="#{ACCENT}">
        <rect x="0" y="4" width="3" height="8">
          <animate attributeName="height" values="8;14;4;10;8" dur="1s" repeatCount="indefinite"/>
          <animate attributeName="y" values="4;1;8;3;4" dur="1s" repeatCount="indefinite"/>
        </rect>
        <rect x="5" y="0" width="3" height="16">
          <animate attributeName="height" values="16;6;12;16;10" dur="1.1s" repeatCount="indefinite"/>
          <animate attributeName="y" values="0;5;2;0;3" dur="1.1s" repeatCount="indefinite"/>
        </rect>
        <rect x="10" y="6" width="3" height="6">
          <animate attributeName="height" values="6;12;4;9;6" dur="0.9s" repeatCount="indefinite"/>
          <animate attributeName="y" values="6;2;8;4;6" dur="0.9s" repeatCount="indefinite"/>
        </rect>
      </g>
    SVG
  end

  def playing_now?
    return false if play.track.duration_ms.blank?

    Time.current < play.played_at + play.track.duration_ms.fdiv(1000).seconds
  end

  def relative_time
    seconds = (Time.current - play.played_at).to_i
    return "just now" if seconds < 60
    return "#{seconds / 60}m ago" if seconds < 3600
    return "#{seconds / 3600}h ago" if seconds < 86_400

    "#{seconds / 86_400}d ago"
  end

  def text(x, y, value, size:, weight:, fill:, max:, spacing: 0)
    %(<text x="#{x}" y="#{y}" font-family="Helvetica, Arial, sans-serif" font-size="#{size}" ) +
      %(font-weight="#{weight}" letter-spacing="#{spacing}" fill="#{fill}">#{esc(value.to_s.truncate(max, omission: "…"))}</text>)
  end

  def esc(value)
    CGI.escapeHTML(value.to_s)
  end
end
