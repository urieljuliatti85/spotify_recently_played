import { useCallback, useEffect, useRef, useState } from "react"
import { currentToken, signOut } from "../lib/spotifyPkce"

const SDK_URL = "https://sdk.scdn.co/spotify-player.js"
const API_HOST = "https://api.spotify.com"
const PLAYER_NAME = "Recently Played"

// Mirrors the embed hook: reports arrive a few hundred ms apart, so "ran out"
// has to tolerate the gap between the last one and the real duration.
const ENDED_EPSILON = 1500

const IDLE_PLAYBACK = { position: 0, duration: 0, isPaused: true }

/**
 * The Web Playback SDK engine — the only one of the two that can set a volume.
 *
 * `state` is what the player bar switches on:
 *   signed-out   nobody has authorized; the embed should play instead
 *   starting     script loading, or the device is not registered yet
 *   ready        this browser is a Spotify device and owns playback
 *   unsupported  signed in, but the account cannot stream (almost always
 *                "not Premium" — Spotify requires it for the SDK)
 *
 * `unsupported` is deliberately not an error state: falling back to the embed
 * is a perfectly good outcome, and a free account is the common case on a page
 * anyone can open.
 */
export function useWebPlayback({
  clientId,
  // Whether a visitor has authorized. Owned by the app rather than sniffed
  // here, because the app is what runs the OAuth callback at boot — this hook
  // has to react to a sign-in that happens after it mounted.
  enabled,
  spotifyId,
  restartKey,
  onEnded,
  // Called when the token dies for good. The app owns `enabled`, so only it
  // can put the page back into its signed-out shape.
  onSignedOut,
  initialVolume = 0.7,
}) {
  const [device, setDevice] = useState("starting") // starting | ready | unsupported
  const [playback, setPlayback] = useState(IDLE_PLAYBACK)
  const [volume, setVolumeState] = useState(initialVolume)

  const playerRef = useRef(null)
  const deviceIdRef = useRef(null)
  const onEndedRef = useRef(onEnded)
  const onSignedOutRef = useRef(onSignedOut)
  // End detection stays disarmed until the track has actually advanced, so the
  // "paused at 0" the SDK reports right after loading cannot look like an end.
  const armedRef = useRef(false)
  const endedRef = useRef(false)

  useEffect(() => {
    onEndedRef.current = onEnded
    onSignedOutRef.current = onSignedOut
  }, [onEnded, onSignedOut])

  const token = useCallback(() => currentToken({ clientId }), [clientId])

  // --- the SDK player -------------------------------------------------------

  const state = enabled ? device : "signed-out"

  useEffect(() => {
    if (!enabled) return undefined

    let cancelled = false

    loadSdk()
      .then((Spotify) => {
        if (cancelled) return

        const player = new Spotify.Player({
          name: PLAYER_NAME,
          volume: initialVolume,
          // Called by the SDK whenever it needs a fresh token, including after
          // one expires mid-session — so refresh lives in one place.
          getOAuthToken: (callback) => {
            token().then((value) => value && callback(value))
          },
        })

        player.addListener("ready", ({ device_id: deviceId }) => {
          if (cancelled) return
          deviceIdRef.current = deviceId
          setDevice("ready")
        })

        player.addListener("not_ready", () => {
          if (!cancelled) setDevice("starting")
        })

        player.addListener("player_state_changed", (next) => {
          if (cancelled || !next) return

          const { position = 0, duration = 0, paused = false } = next
          setPlayback({ position, duration, isPaused: paused })

          if (position > 0) armedRef.current = true

          // The SDK signals the end by pausing back at zero, the same shape the
          // embed uses — reaching the duration is the belt-and-braces case.
          const rewound = paused && position === 0
          const reachedEnd = duration > 0 && position >= duration - ENDED_EPSILON

          if (!armedRef.current || endedRef.current || !(rewound || reachedEnd)) return

          endedRef.current = true
          onEndedRef.current?.()
        })

        // A revoked or wrong-scoped token is not recoverable by retrying, so
        // the stored one goes and the page returns to its signed-out shape.
        player.addListener("authentication_error", () => {
          if (cancelled) return
          signOut()
          onSignedOutRef.current?.()
        })

        // "Premium required" arrives here. Not an error worth showing: the
        // embed plays for this person exactly as it did before they signed in.
        player.addListener("account_error", () => {
          if (!cancelled) setDevice("unsupported")
        })

        player.addListener("initialization_error", () => {
          if (!cancelled) setDevice("unsupported")
        })

        player.connect()
        playerRef.current = player
      })
      .catch(() => {
        if (!cancelled) setDevice("unsupported")
      })

    return () => {
      cancelled = true
      playerRef.current?.disconnect()
      playerRef.current = null
      deviceIdRef.current = null
    }
    // `initialVolume` is read once when the device is created; later changes go
    // through setVolume, so re-creating the player for it would be wrong.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, token])

  // --- playing the selected track ------------------------------------------

  useEffect(() => {
    if (device !== "ready" || !spotifyId) return

    armedRef.current = false
    endedRef.current = false
    setPlayback(IDLE_PLAYBACK)

    let cancelled = false

    token().then((accessToken) => {
      if (cancelled || !accessToken || !deviceIdRef.current) return

      // Starting playback is a Web API call, not an SDK method: the SDK only
      // registers this browser as a device and drives whatever is sent to it.
      fetch(`${API_HOST}/v1/me/player/play?device_id=${deviceIdRef.current}`, {
        method: "PUT",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ uris: [`spotify:track:${spotifyId}`] }),
      }).catch(() => {
        // A failed start leaves the transport where it is rather than tearing
        // the player down; the next selection tries again.
      })
    })

    return () => {
      cancelled = true
    }
  }, [device, spotifyId, restartKey, token])

  // --- controls -------------------------------------------------------------

  const togglePlay = useCallback(() => {
    playerRef.current?.togglePlay()
  }, [])

  const seek = useCallback((positionMs) => {
    playerRef.current?.seek(positionMs)
    // Optimistic, for the same reason the embed does it: the next report is a
    // few hundred ms away and the knob must not snap backwards mid-drag.
    setPlayback((current) => ({ ...current, position: positionMs }))
  }, [])

  const setVolume = useCallback((next) => {
    const clamped = Math.min(1, Math.max(0, next))
    setVolumeState(clamped)
    playerRef.current?.setVolume(clamped)
  }, [])

  return { state, playback, togglePlay, seek, volume, setVolume }
}

// Resolves with the `Spotify` global once the SDK is on the page. The script is
// loaded at most once per document, however many players ask for it.
let sdkPromise = null

function loadSdk() {
  if (window.Spotify) return Promise.resolve(window.Spotify)
  if (sdkPromise) return sdkPromise

  sdkPromise = new Promise((resolve, reject) => {
    // The SDK calls this global the moment it is ready, so it has to exist
    // before the script runs.
    window.onSpotifyWebPlaybackSDKReady = () => resolve(window.Spotify)

    const script = document.createElement("script")
    script.src = SDK_URL
    script.async = true
    script.onerror = () => {
      sdkPromise = null
      reject(new Error("Spotify Web Playback SDK failed to load"))
    }
    document.head.appendChild(script)
  })

  return sdkPromise
}
