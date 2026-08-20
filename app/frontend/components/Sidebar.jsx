import { RANGES, plural } from "../lib/derive"
import { ClockIcon, DiscIcon, NoteIcon, PlayIcon } from "./icons"
import wordmarkUrl from "../images/dekslayer.png"

const RANGE_ICONS = { today: NoteIcon, week: ClockIcon, all: DiscIcon }

export default function Sidebar({ account, range, onRangeChange, recent, selectedPlayId, onSelect }) {
  return (
    <aside className="sidebar">
      <img className="sidebar__wordmark" src={wordmarkUrl} alt="DekSlayer" />

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

      <p className="sidebar__label">Recent plays</p>

      <ol className="sidebar__list">
        {recent.map((play, index) => {
          const isSelected = play.id === selectedPlayId

          return (
            <li key={play.id}>
              <button
                type="button"
                className={`mini ${isSelected ? "mini--selected" : ""}`}
                onClick={() => onSelect(play)}
                aria-pressed={isSelected}
              >
                <span className="mini__index">{String(index + 1).padStart(2, "0")}</span>

                <span className="mini__cover">
                  {play.track.album_image_url ? (
                    <img src={play.track.album_image_url} alt="" loading="lazy" width="40" height="40" />
                  ) : (
                    <span className="cover--empty" />
                  )}
                  <span className="mini__cover-overlay">
                    <PlayIcon size={14} />
                  </span>
                </span>

                <span className="mini__meta">
                  <span className="mini__title">{play.track.name}</span>
                  <span className="mini__artists">{play.track.artists}</span>
                </span>
              </button>
            </li>
          )
        })}

        {recent.length === 0 && <li className="sidebar__empty">Nothing in this range.</li>}
      </ol>

      {account?.display_name && (
        <div className="sidebar__account">
          <span className="sidebar__avatar" aria-hidden="true">
            {account.display_name.trim().charAt(0).toUpperCase()}
          </span>
          <span className="sidebar__account-meta">
            <span className="sidebar__account-name">{account.display_name}</span>
            <span className="sidebar__account-stat">{plural(account.plays_count ?? 0, "play")}</span>
          </span>
        </div>
      )}
    </aside>
  )
}
