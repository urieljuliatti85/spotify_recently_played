import { RANGES } from "../lib/derive"
import { signOut } from "../lib/spotifyPkce"
import ListenerPicker from "./Listener"
import { ClockIcon, DiscIcon, NoteIcon } from "./icons"
import wordmarkUrl from "../images/dekslayer.png"

const RANGE_ICONS = { today: NoteIcon, week: ClockIcon, all: DiscIcon }

export default function Sidebar({
  listeners,
  selectedListenerId,
  onListenerChange,
  range,
  onRangeChange,
  signedIn,
  onSignIn,
  onSignedOut,
}) {
  // Mirrors the auto sign-out on token expiry (useWebPlayback): drop the
  // stored PKCE token first, then let the parent update signedIn.
  function handleSignOut() {
    signOut()
    onSignedOut()
  }
  return (
    <aside className="sidebar">
      <a className="sidebar__home" href="/" aria-label="Go to the main page">
        <img className="sidebar__wordmark" src={wordmarkUrl} alt="DekSlayer" />
      </a>

      {signedIn && (
        <div className="sidebar__account">
          <p className="sidebar__account-title">Signed in with Spotify</p>
          <p className="sidebar__account-hint">
            Full tracks and volume are on for this browser.
          </p>
          <button
            type="button"
            className="btn btn--ghost sidebar__account-btn"
            onClick={handleSignOut}
            title="Sign out of Spotify on this browser"
          >
            Sign out
          </button>
        </div>
      )}

      {!signedIn && onSignIn && (
        <div className="sidebar__account">
          <p className="sidebar__account-title">Play full tracks</p>
          <p className="sidebar__account-hint">
            Sign in with Spotify Premium to unlock full playback and volume control.
          </p>
          <button
            type="button"
            className="btn btn--outline sidebar__account-btn"
            onClick={onSignIn}
            title="Sign in with Spotify Premium to play full tracks and set the volume in the player."
          >
            Sign in with Spotify
          </button>
        </div>
      )}

      <nav className="sidebar__nav" aria-label="Time range">
        {RANGES.map(({ id, label }) => {
          const Icon = RANGE_ICONS[id]
          const isActive = id === range

          return (
            <button
              key={id}
              type="button"
              className={`sidebar__nav-item ${isActive ? "sidebar__nav-item--active" : ""}`}
              onClick={() => onRangeChange(id)}
              aria-pressed={isActive}
            >
              <Icon size={16} />
              <span>{label}</span>
            </button>
          )
        })}
      </nav>

      <ListenerPicker
        listeners={listeners}
        selectedId={selectedListenerId}
        onChange={onListenerChange}
      />
    </aside>
  )
}
