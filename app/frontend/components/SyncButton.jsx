import { useState } from "react"
import { syncNow } from "../lib/api"

// Owner-only (POST /spotify/sync, guarded by HTTP Basic — see
// AdminAuthenticated) — shown to everyone, since the browser only ever
// replays those credentials once they have been handed over somewhere, and
// that is what a 401 here is for: a way to ask for them.
function summarize(payload) {
  const listeners = payload?.listeners ?? []
  if (listeners.length === 0) return "Nothing to sync"

  const imported = listeners.reduce((sum, listener) => sum + (listener.imported ?? 0), 0)
  const failed = listeners.filter((listener) => listener.error).length
  const plays = `${imported} new play${imported === 1 ? "" : "s"}`

  return failed === 0 ? `Synced ${plays}` : `Synced ${plays} — ${failed} listener${failed === 1 ? "" : "s"} failed`
}

export default function SyncButton({ ownerPath, view }) {
  const [state, setState] = useState("idle")
  const [message, setMessage] = useState(null)
  const [needsOwner, setNeedsOwner] = useState(false)

  function sync() {
    setState("syncing")
    setNeedsOwner(false)
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
        // A 401 means the browser has never handed over ADMIN_PASSWORD —
        // there is nothing to say about it beyond how to fix that.
        setNeedsOwner(cause.status === 401)
        setMessage(cause.status === 401 ? null : cause.message)
        setState("error")
      })
  }

  return (
    <div className="sync">
      <button type="button" className="sync-btn" onClick={sync} disabled={state === "syncing"}>
        {state === "syncing" ? "Syncing…" : "Sync"}
      </button>

      {state === "error" && needsOwner && ownerPath && (
        <a className="sync__hint" href={`${ownerPath}?view=${encodeURIComponent(view)}`}>
          Sign in to sync
        </a>
      )}
      {state === "error" && !needsOwner && (
        <span className="sync__hint sync__hint--error">{message || "Sync failed"}</span>
      )}
      {state === "done" && <span className="sync__hint">{message}</span>}
    </div>
  )
}
