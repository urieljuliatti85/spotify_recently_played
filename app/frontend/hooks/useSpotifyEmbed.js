import { useCallback, useEffect, useRef, useState } from "react"

const READY_TIMEOUT = 8000

// The first report at position 0 is what tells us the new track is mounted and
// ready to be told to play. This is the backstop for when that report never
// arrives (a cold iframe, a stalled network) — long enough that the outgoing
// track's last reports have already drained.
const PLAY_FALLBACK = 1500

// Position reports arrive a few hundred ms apart, so "reached the end" has to
// tolerate the gap between the last report and the real duration.
const ENDED_EPSILON = 1500

const IDLE_PLAYBACK = { position: 0, duration: 0, isPaused: true }

// `loadUri` is the deprecated name for what is now `loadEntity`. Older embeds
// in the wild still only answer to the former, so prefer the current method and
// keep the old one as the fallback.
function loadInto(controller, uri) {
  if (typeof controller.loadEntity === "function") {
    controller.loadEntity(uri)
    return
  }

  controller.loadUri(uri)
}

// Resolves once Spotify's iframe API is on the page. The layout registers the
// global callback before the script loads, so this can't miss the event.
function whenApiReady() {
  return new Promise((resolve, reject) => {
    if (window.spotifyIframeApi) {
      resolve(window.spotifyIframeApi)
      return
    }

    const timer = setTimeout(() => {
      window.removeEventListener("spotify-iframe-api-ready", onReady)
      reject(new Error("Spotify iframe API did not load"))
    }, READY_TIMEOUT)

    function onReady() {
      clearTimeout(timer)
      resolve(window.spotifyIframeApi)
    }

    window.addEventListener("spotify-iframe-api-ready", onReady, { once: true })
  })
}

/**
 * Keeps one Spotify embed alive for the whole session and swaps the track it
 * plays. Falls back to a plain embed iframe if the API script is unavailable
 * (ad blockers, offline), which still plays — it just needs an extra click.
 *
 * `restartKey` identifies the *selection*, not the track: the feed is full of
 * repeats, and picking one has to restart playback even when the track that is
 * already loaded is the same one.
 *
 * `onEnded` fires once per track, when playback runs out. `playback` mirrors
 * the embed's own position so the page can draw its own transport controls;
 * position and duration are milliseconds, while `seek` takes seconds — that
 * mismatch is the embed API's, not ours.
 */
export function useSpotifyEmbed(spotifyId, { onEnded, restartKey } = {}) {
  const containerRef = useRef(null)
  const controllerRef = useRef(null)
  const [state, setState] = useState("loading") // loading | ready | unavailable
  const [playback, setPlayback] = useState(IDLE_PLAYBACK)

  // The listener is registered once for the embed's whole life, so the
  // callback and the per-track bookkeeping live in refs it can read without
  // ever having to re-subscribe.
  const onEndedRef = useRef(onEnded)
  const endedRef = useRef(false)
  // End detection stays disarmed until the loaded track actually advances.
  // Before that, a report can still describe the outgoing track — and one of
  // those looks exactly like "the current track just finished".
  const armedRef = useRef(false)
  // Set while a load waits for the embed to mount the new track.
  const pendingPlayRef = useRef(false)
  const loadedUriRef = useRef(null)
  // The URI the embed has been told to load, which reports are matched against.
  const wantedUriRef = useRef(null)

  useEffect(() => {
    onEndedRef.current = onEnded
  }, [onEnded])

  const start = useCallback(() => {
    pendingPlayRef.current = false
    try {
      controllerRef.current?.play()
    } catch {
      // Browsers may refuse programmatic playback — the embed's own play
      // button still works.
    }
  }, [])

  // The embed has no "ended" event — it only reports position/duration a few
  // times a second. Two shapes mean the track ran out: playback reached the
  // duration, or the scrubber snapped back to 0 and paused (what the embed
  // does when a 30s preview runs out, where `duration` is the full track and
  // never gets reached). A manual pause never rewinds, so it can't be
  // mistaken for either.
  const handlePlaybackUpdate = useCallback(
    (event) => {
      const { position = 0, duration = 0, isPaused = false, playingURI } = event?.data ?? {}

      // Between the load and the new track mounting, the embed keeps reporting
      // the outgoing one — and those reports read as "position is at duration",
      // which is exactly the shape of a track that just ended, so they have to
      // be dropped. `playingURI` names the track a report is about; the embed
      // builds that payload inside its own iframe, so where it doesn't send the
      // field, the reset to zero is the only trustworthy sign the swap landed.
      const staleReport =
        playingURI && wantedUriRef.current
          ? playingURI !== wantedUriRef.current
          : pendingPlayRef.current && position !== 0

      if (staleReport) return

      // First report for the track we asked for: the embed has it mounted, so
      // play() will now land on the right thing.
      if (pendingPlayRef.current) start()

      setPlayback({ position, duration, isPaused })

      // Real progress on this track: from here a report can mean "finished".
      if (position > 0) armedRef.current = true

      const rewound = isPaused && position === 0
      const reachedEnd = duration > 0 && position >= duration - ENDED_EPSILON

      if (!armedRef.current || endedRef.current || !(rewound || reachedEnd)) return

      endedRef.current = true
      onEndedRef.current?.()
    },
    [start]
  )

  useEffect(() => {
    let cancelled = false

    whenApiReady()
      .then((api) => {
        if (cancelled || !containerRef.current) return

        api.createController(
          containerRef.current,
          { width: "100%", height: 152 },
          (controller) => {
            if (cancelled) {
              controller.destroy()
              return
            }

            controller.addListener("playback_update", handlePlaybackUpdate)
            controllerRef.current = controller
            setState("ready")
          }
        )
      })
      .catch(() => {
        if (!cancelled) setState("unavailable")
      })

    return () => {
      cancelled = true
      controllerRef.current?.destroy()
      controllerRef.current = null
      loadedUriRef.current = null
      wantedUriRef.current = null
    }
  }, [handlePlaybackUpdate])

  // Swap the loaded track whenever the selection changes.
  useEffect(() => {
    const controller = controllerRef.current
    if (!controller || !spotifyId) return

    // Fresh selection, fresh end detection — otherwise the previous track's
    // progress would make the new one look finished on its first report.
    armedRef.current = false
    endedRef.current = false
    setPlayback(IDLE_PLAYBACK)

    const uri = `spotify:track:${spotifyId}`

    // Re-selecting the track that is already loaded has to be restarted by
    // hand: loadUri has nothing to swap, so the embed would sit wherever the
    // last play left it — at the end, silent, with autoplay stuck behind it.
    if (loadedUriRef.current === uri) {
      pendingPlayRef.current = false
      try {
        controller.restart()
      } catch {
        // Ignored: play() below still resumes from wherever it stopped.
      }
      start()
      return
    }

    loadedUriRef.current = uri
    wantedUriRef.current = uri
    pendingPlayRef.current = true
    loadInto(controller, uri)

    const timer = setTimeout(() => {
      if (pendingPlayRef.current) start()
    }, PLAY_FALLBACK)

    return () => clearTimeout(timer)
  }, [spotifyId, restartKey, state, start])

  const togglePlay = useCallback(() => {
    try {
      controllerRef.current?.togglePlay()
    } catch {
      // Same story as autoplay: the embed's own controls remain the fallback.
    }
  }, [])

  // Optimistic: the embed only reports the new position on its next update, so
  // moving the knob locally keeps a drag from snapping backwards mid-gesture.
  const seek = useCallback((positionMs) => {
    try {
      controllerRef.current?.seek(positionMs / 1000)
      setPlayback((current) => ({ ...current, position: positionMs }))
    } catch {
      // Ignored: the progress bar just stays where the embed reports it.
    }
  }, [])

  return { containerRef, state, playback, togglePlay, seek }
}
