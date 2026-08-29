import { useState } from "react"
import { syncNow } from "../lib/api"

// Public (POST /spotify/sync) — anyone can trigger a sync, rate-limited
// server-side to keep it from burning through Spotify's quota.
function summarize(payload) {
  const listeners = payload?.listeners ?? []
  if (listeners.length === 0) return "Nothing to sync"

  const imported = listeners.reduce((sum, listener) => sum + (listener.imported ?? 0), 0)
  const failed = listeners.filter((listener) => listener.error).length
  const plays = `${imported} new play${imported === 1 ? "" : "s"}`

  return failed === 0 ? `Synced ${plays}` : `Synced ${plays} — ${failed} listener${failed === 1 ? "" : "s"} failed`
}

export default function SyncButton() {
  const [state, setState] = useState("idle")
  const [message, setMessage] = useState(null)

  function sync() {
    setState("syncing")
    setMessage(null)

    syncNow()
      .then((payload) => {
        setMessage(summarize(payload))
        setState("done")
        // The point of syncing from here is to see the result without
        // reaching for the browser's own refresh — a full reload, not a
        // re-fetch, so every view (not just the plays feed) picks it up.
        window.location.reload()
      })
      .catch((cause) => {
        setMessage(cause.status === 429 ? "Too many syncs — try again in a bit" : cause.message)
        setState("error")
      })
  }

  return (
    <div className="sync">
      <button type="button" className="sync-btn" onClick={sync} disabled={state === "syncing"}>
        {state === "syncing" ? "Syncing…" : "Sync"}
      </button>

      {state === "error" && (
        <span className="sync__hint sync__hint--error">{message || "Sync failed"}</span>
      )}
      {state === "done" && <span className="sync__hint">{message}</span>}
    </div>
  )
}
