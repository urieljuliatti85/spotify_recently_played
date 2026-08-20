import { Fragment } from "react"
import { useSpotifyEmbed } from "../hooks/useSpotifyEmbed"
import { creditsOf } from "../lib/derive"
import { duration as formatDuration } from "../lib/format"
import { CloseIcon, ExternalIcon, NextIcon, PauseIcon, PlayIcon, PrevIcon, ShuffleIcon } from "./icons"

function clock(ms) {
  return formatDuration(ms) ?? "0:00"
}

export default function PlayerBar({
  play,
  autoplay,
  onToggleAutoplay,
  onEnded,
  onClose,
  onPrev,
  onNext,
  onOpenArtist,
  hasPrev,
  hasNext,
}) {
  const { containerRef, state, playback, togglePlay, seek } = useSpotifyEmbed(
    play?.track?.spotify_id,
    { onEnded }
  )

  const { track } = play
  // The embed reports the track's real duration once it loads; until then the
  // stored duration keeps the scrubber from rendering at zero width.
  const total = playback.duration || track.duration_ms || 0
  const controllable = state === "ready"

  return (
    <div className="playerbar" role="region" aria-label="Player">
      <div className="playerbar__now">
        <span className="playerbar__cover">
          {track.album_image_url ? (
            <img src={track.album_image_url} alt="" width="52" height="52" />
          ) : (
            <span className="cover--empty" />
          )}
        </span>

        <span className="playerbar__meta">
          <span className="playerbar__track">{track.name}</span>
          <span className="playerbar__artists">
            {creditsOf(track).map((credit, index) => (
              <Fragment key={credit.key}>
                {index > 0 && ", "}
                <button type="button" className="linkish" onClick={() => onOpenArtist(credit)}>
                  {credit.name}
                </button>
              </Fragment>
            ))}
          </span>
        </span>

        <a
          className="playerbar__link"
          href={track.spotify_url}
          target="_blank"
          rel="noreferrer noopener"
          title="Open in Spotify"
          aria-label={`Open ${track.name} in Spotify`}
        >
          <ExternalIcon size={15} />
        </a>
      </div>

      <div className="playerbar__center">
        <div className="transport">
          <button
            type="button"
            className="transport__btn"
            onClick={onPrev}
            disabled={!hasPrev}
            aria-label="Previous track"
          >
            <PrevIcon size={18} />
          </button>

          <button
            type="button"
            className="transport__btn transport__btn--main"
            onClick={togglePlay}
            disabled={!controllable}
            aria-label={playback.isPaused ? "Play" : "Pause"}
          >
            {playback.isPaused ? <PlayIcon size={20} /> : <PauseIcon size={20} />}
          </button>

          <button
            type="button"
            className="transport__btn"
            onClick={onNext}
            disabled={!hasNext}
            aria-label="Next track"
          >
            <NextIcon size={18} />
          </button>
        </div>

        <div className="scrubber">
          <span className="scrubber__time">{clock(playback.position)}</span>

          <input
            className="scrubber__range"
            type="range"
            min="0"
            max={total || 1}
            step="1000"
            value={Math.min(playback.position, total || 1)}
            onChange={(event) => seek(Number(event.target.value))}
            disabled={!controllable || total === 0}
            aria-label="Seek"
            style={{ "--progress": `${total ? (playback.position / total) * 100 : 0}%` }}
          />

          <span className="scrubber__time">{clock(total)}</span>
        </div>
      </div>

      <div className="playerbar__side">
        <button
          type="button"
          className={`icon-toggle ${autoplay ? "icon-toggle--on" : ""}`}
          onClick={onToggleAutoplay}
          aria-pressed={autoplay}
          title="Play the next track automatically"
        >
          <ShuffleIcon size={16} />
          <span className="icon-toggle__label">Autoplay</span>
        </button>

        <button type="button" className="icon-btn" onClick={onClose} aria-label="Close player">
          <CloseIcon size={14} />
        </button>
      </div>

      {/* Spotify's API replaces this node with the embed iframe. It stays in
          the layout at 1px so the custom transport above drives it — removing
          it from the flow would tear down playback. */}
      <div className={`playerbar__embed ${controllable ? "playerbar__embed--hidden" : ""}`}>
        <div ref={containerRef} />

        {state === "loading" && <p className="playerbar__hint">Loading the player…</p>}

        {state === "unavailable" && (
          <iframe
            title={`Player for ${track.name}`}
            src={`https://open.spotify.com/embed/track/${track.spotify_id}?theme=0`}
            width="100%"
            height="80"
            frameBorder="0"
            loading="lazy"
            allow="autoplay; clipboard-write; encrypted-media; fullscreen; picture-in-picture"
          />
        )}
      </div>
    </div>
  )
}
