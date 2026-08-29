import { SearchIcon } from "./icons"
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
