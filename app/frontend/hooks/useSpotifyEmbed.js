import { useCallback, useEffect, useRef, useState } from "react"

const READY_TIMEOUT = 8000

// Position reports arrive a few hundred ms apart, so "reached the end" has to
// tolerate the gap between the last report and the real duration.
const ENDED_EPSILON = 1500

const IDLE_PLAYBACK = { position: 0, duration: 0, isPaused: true }

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
 * `onEnded` fires once per track, when playback runs out. `playback` mirrors
 * the embed's own position so the page can draw its own transport controls;
 * position and duration are milliseconds, while `seek` takes seconds — that
 * mismatch is the embed API's, not ours.
 */
export function useSpotifyEmbed(spotifyId, { onEnded } = {}) {
  const containerRef = useRef(null)
  const controllerRef = useRef(null)
  const [state, setState] = useState("loading") // loading | ready | unavailable
  const [playback, setPlayback] = useState(IDLE_PLAYBACK)

  // The listener is registered once for the embed's whole life, so the
  // callback and the per-track bookkeeping live in refs it can read without
  // ever having to re-subscribe.
  const onEndedRef = useRef(onEnded)
  const furthestRef = useRef(0)
  const endedRef = useRef(false)

  useEffect(() => {
    onEndedRef.current = onEnded
  }, [onEnded])

  // The embed has no "ended" event — it only reports position/duration a few
  // times a second. Two shapes mean the track ran out: playback reached the
  // duration, or the scrubber snapped back to 0 and paused (what the embed
  // does when a 30s preview runs out, where `duration` is the full track and
  // never gets reached). A manual pause never rewinds, so it can't be
  // mistaken for either.
  const handlePlaybackUpdate = useCallback((event) => {
    const { position = 0, duration = 0, isPaused = false } = event?.data ?? {}

    setPlayback({ position, duration, isPaused })

    const startedPlaying = furthestRef.current > 0
    const rewound = isPaused && position === 0 && startedPlaying
    const reachedEnd = duration > 0 && position >= duration - ENDED_EPSILON

    furthestRef.current = Math.max(furthestRef.current, position)

    if (endedRef.current || !(rewound || reachedEnd)) return

    endedRef.current = true
    onEndedRef.current?.()
  }, [])

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
    }
  }, [handlePlaybackUpdate])

  // Swap the loaded track whenever the selection changes.
  useEffect(() => {
    const controller = controllerRef.current
    if (!controller || !spotifyId) return

    // Fresh track, fresh end detection — otherwise the previous track's
    // progress would make the new one look finished on its first report.
    furthestRef.current = 0
    endedRef.current = false
    setPlayback(IDLE_PLAYBACK)

    controller.loadUri(`spotify:track:${spotifyId}`)

    // loadUri only queues the track; play() has to wait for the new track to
    // be mounted inside the embed.
    const timer = setTimeout(() => {
      try {
        controller.play()
      } catch {
        // Browsers may refuse programmatic playback — the embed's own play
        // button still works.
      }
    }, 400)

    return () => clearTimeout(timer)
  }, [spotifyId, state])

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
