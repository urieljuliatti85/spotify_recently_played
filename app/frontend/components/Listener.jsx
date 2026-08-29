import { ExternalIcon } from "./icons"

// A listener's face, or their initial when Spotify has no photo for them.
export function ListenerAvatar({ listener, size = 24 }) {
  const initial = (listener?.name ?? "?").trim().charAt(0).toUpperCase() || "?"

  return listener?.avatar_url ? (
    <img
      className="listener__avatar"
      src={listener.avatar_url}
      alt=""
      width={size}
      height={size}
      loading="lazy"
      style={{ width: size, height: size }}
    />
  ) : (
    <span
      className="listener__avatar listener__avatar--initial"
      aria-hidden="true"
      style={{ width: size, height: size, fontSize: Math.round(size * 0.45) }}
    >
      {initial}
    </span>
  )
}

// The "who played this" tag on a feed row. Only worth the space once more than
// one person is on the feed, which is why the feed decides whether to show it.
export function ListenerTag({ listener, onSelect }) {
  if (!listener) return null

  const body = (
    <>
      <ListenerAvatar listener={listener} size={20} />
      <span className="listener-tag__name">{listener.name}</span>
    </>
  )

  if (!onSelect) return <span className="listener-tag">{body}</span>

  return (
    <button
      type="button"
      className="listener-tag listener-tag--button"
      onClick={(event) => {
        event.stopPropagation()
        onSelect(listener)
      }}
      aria-label={`Show only what ${listener.name} played`}
    >
      {body}
    </button>
  )
}

// The sidebar switcher: everyone, or one person at a time.
export default function ListenerPicker({ listeners, selectedId, onChange }) {
  if (listeners.length === 0) return null

  const total = listeners.reduce((sum, listener) => sum + (listener.plays_count ?? 0), 0)

  return (
    <>
      <p className="sidebar__label">Listeners</p>

      <ul className="listeners">
        {listeners.length > 1 && (
          <li>
            <button
              type="button"
              className={`listener ${selectedId === null ? "listener--active" : ""}`}
              onClick={() => {
                window.location.href = "/?view=listeners"
              }}
              aria-pressed={selectedId === null}
            >
              <span className="listener__avatar listener__avatar--all" aria-hidden="true">
                {listeners.length}
              </span>
              <span className="listener__meta">
                <span className="listener__name">Everyone</span>
                <span className="listener__stat">{total.toLocaleString("en-US")} plays</span>
              </span>
            </button>
          </li>
        )}

        {listeners.map((listener) => (
          <li key={listener.id} className="listener-row">
            <button
              type="button"
              className={`listener ${selectedId === listener.id ? "listener--active" : ""}`}
              onClick={() => onChange(listener.id)}
              aria-pressed={selectedId === listener.id}
            >
              <ListenerAvatar listener={listener} size={32} />
              <span className="listener__meta">
                <span className="listener__name">
                  {listener.name}
                  {listener.owner && <span className="listener__badge">owner</span>}
                </span>
                <span className="listener__stat">
                  {(listener.plays_count ?? 0).toLocaleString("en-US")} plays
                </span>
              </span>
            </button>

            {listener.spotify_url && (
              <a
                className="listener__profile-link"
                href={listener.spotify_url}
                target="_blank"
                rel="noreferrer noopener"
                title={`Open ${listener.name}'s Spotify profile`}
                aria-label={`Open ${listener.name}'s Spotify profile`}
                onClick={(event) => event.stopPropagation()}
              >
                <ExternalIcon size={13} />
              </a>
            )}
          </li>
        ))}
      </ul>
    </>
  )
}
