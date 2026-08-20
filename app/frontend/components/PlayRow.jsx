import { duration, relativeTime, timeOfDay } from "../lib/format"

export default function PlayRow({ play, isSelected, onSelect }) {
  const { track } = play
  const relative = relativeTime(play.played_at)

  return (
    <li className={`play ${isSelected ? "play--selected" : ""}`}>
      <button
        type="button"
        className="play__main"
        onClick={() => onSelect(play)}
        aria-pressed={isSelected}
        aria-label={`Tocar ${track.name}, de ${track.artists}`}
      >
        <span className="play__cover">
          {track.album_image_url ? (
            <img src={track.album_image_url} alt="" loading="lazy" width="56" height="56" />
          ) : (
            <span className="play__cover--empty" aria-hidden="true" />
          )}
          <span className="play__cover-overlay" aria-hidden="true">
            {isSelected ? <PauseGlyph /> : <PlayGlyph />}
          </span>
        </span>

        <span className="play__meta">
          <span className="play__title">
            {track.name}
            {track.explicit && <span className="play__explicit" title="Conteúdo explícito">E</span>}
          </span>
          <span className="play__artists">{track.artists}</span>
        </span>

        <span className="play__timing">
          <time dateTime={play.played_at} title={new Date(play.played_at).toLocaleString("pt-BR")}>
            {timeOfDay(play.played_at)}
          </time>
          {relative && <span className="play__relative">{relative}</span>}
        </span>

        {track.duration_ms && <span className="play__duration">{duration(track.duration_ms)}</span>}
      </button>

      <a
        className="play__external"
        href={track.spotify_url}
        target="_blank"
        rel="noreferrer noopener"
        title="Abrir no Spotify"
        aria-label={`Abrir ${track.name} no Spotify`}
      >
        ↗
      </a>
    </li>
  )
}

function PlayGlyph() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
      <path d="M8 5.5v13l11-6.5z" />
    </svg>
  )
}

function PauseGlyph() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
      <path d="M7 5h3.5v14H7zm6.5 0H17v14h-3.5z" />
    </svg>
  )
}
