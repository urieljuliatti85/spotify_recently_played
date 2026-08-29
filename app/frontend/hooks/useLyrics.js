import { useEffect, useState } from "react"
import { fetchLyrics } from "../lib/api"
import { parseSyncedLyrics } from "../lib/format"

const IDLE = { state: "idle", plainLyrics: null, syncedLines: [], instrumental: false }

// Fetches lrclib's lyrics for one track at a time — unlike the feed's
// YouTube matches, this only ever asks about whatever is currently playing,
// and lrclib has no daily quota to protect, so there is no batching or
// per-request cap to worry about here.
export function useLyrics(spotifyTrackId) {
  const [result, setResult] = useState(IDLE)

  useEffect(() => {
    if (!spotifyTrackId) {
      setResult(IDLE)
      return undefined
    }

    setResult({ ...IDLE, state: "loading" })
    const controller = new AbortController()

    fetchLyrics(spotifyTrackId, { signal: controller.signal })
      .then((payload) => {
        setResult({
          state: payload.found ? "ready" : "missing",
          plainLyrics: payload.plain_lyrics,
          syncedLines: parseSyncedLyrics(payload.synced_lyrics),
          instrumental: payload.instrumental,
        })
      })
      .catch((error) => {
        if (error.name !== "AbortError") setResult({ ...IDLE, state: "error" })
      })

    return () => controller.abort()
  }, [spotifyTrackId])

  return result
}
