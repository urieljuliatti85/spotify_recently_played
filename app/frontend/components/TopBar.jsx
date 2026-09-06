import { useEffect, useRef, useState } from "react"
import { ChevronDownIcon, SearchIcon } from "./icons"
import SyncButton from "./SyncButton"

export const VIEWS = [
  { id: "overview", label: "Overview" },
  { id: "tracks", label: "Tracks" },
  { id: "albums", label: "Albums" },
  { id: "artists", label: "Artists" },
  { id: "listeners", label: "Listeners" },
  { id: "playlists", label: "Playlists" },
  // Public, same as the data behind it (Spotify::MetricsController) —
  // request counts, latency and sync outcomes are operational detail, not
  // anything private about a listener.
  { id: "metrics", label: "Metrics" },
]

// Below ~640px the seven-tab row no longer fits, and scrolling it sideways
// just moved the "too long" problem instead of fixing it. This collapses to
// a single button naming the current view, which opens a vertical list —
// both live in the DOM at once and CSS picks one per breakpoint, so there is
// no layout jump at the boundary and no separate mobile-only data path.
function ViewMenu({ view, onViewChange }) {
  const [open, setOpen] = useState(false)
  const rootRef = useRef(null)
  const current = VIEWS.find((v) => v.id === view) ?? VIEWS[0]

  useEffect(() => {
    if (!open) return

    function handlePointerDown(event) {
      if (!rootRef.current?.contains(event.target)) setOpen(false)
    }
    function handleKeyDown(event) {
      if (event.key === "Escape") setOpen(false)
    }

    document.addEventListener("pointerdown", handlePointerDown)
    document.addEventListener("keydown", handleKeyDown)
    return () => {
      document.removeEventListener("pointerdown", handlePointerDown)
      document.removeEventListener("keydown", handleKeyDown)
    }
  }, [open])

  return (
    <div className="view-menu" ref={rootRef}>
      <button
        type="button"
        className="view-menu__trigger"
        onClick={() => setOpen((was) => !was)}
        aria-haspopup="listbox"
        aria-expanded={open}
      >
        {current.label}
        <ChevronDownIcon size={16} />
      </button>

      {open && (
        <ul className="view-menu__list" role="listbox">
          {VIEWS.map(({ id, label }) => (
            <li key={id}>
              <button
                type="button"
                className={`view-menu__option ${id === view ? "view-menu__option--active" : ""}`}
                role="option"
                aria-selected={id === view}
                onClick={() => {
                  onViewChange(id)
                  setOpen(false)
                }}
              >
                {label}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

export default function TopBar({ view, onViewChange, query, onQueryChange, lastSyncedAt }) {
  const syncedAt = lastSyncedAt && new Date(lastSyncedAt)

  return (
    <div className="topbar">
      <nav className="tabs" aria-label="View">
        {VIEWS.map(({ id, label }) => (
          <button
            key={id}
            type="button"
            className={`tabs__tab ${id === view ? "tabs__tab--active" : ""}`}
            onClick={() => onViewChange(id)}
            aria-pressed={id === view}
          >
            {label}
          </button>
        ))}
      </nav>

      <ViewMenu view={view} onViewChange={onViewChange} />

      <div className="topbar__right">
        <label className="search">
          <SearchIcon size={16} />
          <input
            type="search"
            value={query}
            onChange={(event) => onQueryChange(event.target.value)}
            placeholder="Search tracks, artists, albums…"
            aria-label="Search tracks, artists, albums"
          />
        </label>

        {syncedAt && (
          <p className="topbar__synced" title={syncedAt.toLocaleString("en-US")}>
            Synced {syncedAt.toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" })}
          </p>
        )}

        <SyncButton />
      </div>
    </div>
  )
}
