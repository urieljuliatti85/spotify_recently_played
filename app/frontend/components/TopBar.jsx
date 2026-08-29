import { SearchIcon } from "./icons"
import SyncButton from "./SyncButton"

export const VIEWS = [
  { id: "overview", label: "Overview" },
  { id: "tracks", label: "Tracks" },
  { id: "albums", label: "Albums" },
  { id: "artists", label: "Artists" },
  { id: "listeners", label: "Listeners" },
  { id: "playlists", label: "Playlists" },
  { id: "discogs", label: "Discogs" },
]

// Not in VIEWS: it's operational detail (see Spotify::MetricsSnapshot),
// shown only once /api/status has said `admin`, same as the rest of the
// owner-only surface — unlike a Sync button's 401, a visitor should never
// even see this tab exists.
const ADMIN_VIEWS = [ { id: "metrics", label: "Metrics" } ]

export default function TopBar({ view, onViewChange, query, onQueryChange, lastSyncedAt, ownerPath, isAdmin }) {
  const syncedAt = lastSyncedAt && new Date(lastSyncedAt)
  const tabs = isAdmin ? [ ...VIEWS, ...ADMIN_VIEWS ] : VIEWS

  return (
    <div className="topbar">
      <nav className="tabs" aria-label="View">
        {tabs.map(({ id, label }) => (
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

        <SyncButton ownerPath={ownerPath} view={view} />
      </div>
    </div>
  )
}
