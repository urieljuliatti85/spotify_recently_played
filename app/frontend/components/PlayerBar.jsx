import { Fragment, useCallback, useMemo, useState } from "react"
import { useLyrics } from "../hooks/useLyrics"
import { useSpotifyEmbed } from "../hooks/useSpotifyEmbed"
import { useWebPlayback } from "../hooks/useWebPlayback"
import { creditsOf } from "../lib/derive"
import { duration as formatDuration } from "../lib/format"
import {
  CloseIcon,
  ExternalIcon,
  NextIcon,
  NoteIcon,
  PauseIcon,
  PlayIcon,
  PrevIcon,
  ShuffleIcon,
  VolumeIcon,
} from "./icons"
import LyricsPanel from "./LyricsPanel"
import VolumeControl from "./VolumeControl"

const VOLUME_KEY = "volume"

function clock(ms) {
  return formatDuration(ms) ?? "0:00"
}

/**
 * Whatever belongs where a volume control would go, which depends on which
 * engine is playing. Only the SDK can set a level; under the embed the honest
 * thing is a note about where the volume actually lives, because a slider
 * there would move without changing anything.
 */
function VolumeArea({ state, volume, onChange }) {
  if (state === "ready") return <VolumeControl volume={volume} onChange={onChange} />

  if (state === "starting") {
    return (
      <p className="playerbar__volume">
        <VolumeIcon size={15} />
        <span className="playerbar__volume-label">Connecting…</span>
      </p>
    )
  }

  // Two ways to land here, and they are not the same sentence: signed in with
  // an account that cannot stream (free — the SDK is Premium-only), or no way
  // to sign in at all because the site has no Spotify client id configured.
  // Either way the embed is playing; only the reason differs.
  return (
    <p
      className="playerbar__volume"
      title={
        state === "unsupported"
          ? "This Spotify account cannot stream here — the volume slider needs Premium — so the embedded player is being used. Use your device's volume."
          : "The embedded player has no volume control. Use your device's volume."
      }
    >
      <VolumeIcon size={15} />
      <span className="playerbar__volume-label">System volume</span>
    </p>
  )
}

function readVolumePreference() {
  try {
    const stored = Number(window.localStorage.getItem(VOLUME_KEY))
    return Number.isFinite(stored) && stored >= 0 && stored <= 1 ? stored : 0.7
  } catch {
    return 0.7
  }
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
  clientId,
  signedIn,
  onSignedOut,
}) {
  // The play id, not the track id, is what restarts either engine: the same
  // track turns up all over the feed, and picking one has to play it again.
  const restartKey = play?.id
  const spotifyId = play?.track?.spotify_id

  // Read once, not on every render: this is the level the device is created
  // with, and later changes go through setVolume.
  const initialVolume = useMemo(readVolumePreference, [])

  const sdk = useWebPlayback({
    clientId,
    enabled: signedIn,
    spotifyId,
    restartKey,
    onEnded,
    onSignedOut,
    initialVolume,
  })

  // Whichever engine is playing, only one may hold the track: handing the
  // embed a uri while the SDK owns playback would play the song twice, out of
  // sync with itself.
  const sdkDriving = sdk.state === "ready"
  const embed = useSpotifyEmbed(sdkDriving ? null : spotifyId, { onEnded, restartKey })

  const { containerRef } = embed
  const { playback, togglePlay, seek } = sdkDriving ? sdk : embed

  // Fetched eagerly on every track change, panel open or not: lrclib has no
  // daily quota to protect (unlike the feed's YouTube matches), so there is
  // no reason to make a visitor click first to find out whether lyrics exist.
  const [lyricsOpen, setLyricsOpen] = useState(false)
  const lyrics = useLyrics(spotifyId)

  const { setVolume } = sdk
  const changeVolume = useCallback(
    (next) => {
      setVolume(next)
      try {
        window.localStorage.setItem(VOLUME_KEY, String(next))
      } catch {
        // Private browsing: the level just won't survive a reload.
      }
    },
    [setVolume]
  )

  // Nothing selected yet: every hook above already tolerates a missing
  // spotifyId (they just stay idle), so this has to come after all of them
  // — hooks can't be conditional, and this early return can't skip any.
  // The bar itself stays on screen either way; only its content changes.
  if (!play) {
    return (
      <div className="playerbar playerbar--idle" role="region" aria-label="Player">
        <p className="playerbar__idle-hint">
          <NoteIcon size={16} />
          Pick a track from the feed to start listening.
        </p>
      </div>
    )
  }

  const { track } = play
  // The engine reports the track's real duration once it loads; until then the
  // stored duration keeps the scrubber from rendering at zero width.
  const total = playback.duration || track.duration_ms || 0
  const controllable = sdkDriving || embed.state === "ready"

  return (
    <>
      {lyricsOpen && (
        <LyricsPanel
          state={lyrics.state}
          plainLyrics={lyrics.plainLyrics}
          syncedLines={lyrics.syncedLines}
          instrumental={lyrics.instrumental}
          position={playback.position}
          onClose={() => setLyricsOpen(false)}
        />
      )}

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
          <VolumeArea state={sdk.state} volume={sdk.volume} onChange={changeVolume} />

          <button
            type="button"
            className={`icon-toggle ${lyricsOpen ? "icon-toggle--on" : ""}`}
            onClick={() => setLyricsOpen((open) => !open)}
            aria-pressed={lyricsOpen}
            title="Show lyrics"
          >
            <NoteIcon size={16} />
            <span className="icon-toggle__label">Lyrics</span>
          </button>

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

          <button type="button" className="icon-btn" onClick={onClose} aria-label="Stop playback" title="Stop playback">
            <CloseIcon size={14} />
          </button>
        </div>

        {/* Spotify's API replaces this node with the embed iframe. It stays in
            the layout at 1px so the custom transport above drives it — removing
            it from the flow would tear down playback. */}
        <div className={`playerbar__embed ${controllable ? "playerbar__embed--hidden" : ""}`}>
          <div ref={containerRef} />

          {embed.state === "loading" && <p className="playerbar__hint">Loading the player…</p>}

          {/* The transport above talks to the embed through Spotify's script. With
              the script blocked there is nothing on the other end, so the play
              button and the scrubber are disabled — and a dead button with no
              explanation reads as a broken site. The fallback below does play;
              this says so. */}
          {embed.state === "unavailable" && (
            <p className="playerbar__hint">
              Something on this browser is blocking Spotify&apos;s player script, so the
              controls above can&apos;t reach it. Play from here instead.
            </p>
          )}

          {embed.state === "unavailable" && (
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
    </>
  )
}
