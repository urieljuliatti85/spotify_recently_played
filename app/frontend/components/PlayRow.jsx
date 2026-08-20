import { duration, relativeTime, timeOfDay } from "../lib/format"
import { ExternalIcon, PauseIcon, PlayIcon } from "./icons"

export default function PlayRow({ play, index, isSelected, onSelect }) {
  const { track } = play
  const relative = relativeTime(play.played_at)

  return (
    <li className={`row ${isSelected ? "row--selected" : ""}`}>
      <button
        type="button"
        className="row__main"
        onClick={() => onSelect(play)}
        aria-pressed={isSelected}
        aria-label={`Play ${track.name} by ${track.artists}`}
      >
        <span className="row__index">{String(index + 1).padStart(2, "0")}</span>

        <span className="row__cover">
          {track.album_image_url ? (
            <img src={track.album_image_url} alt="" loading="lazy" width="48" height="48" />
          ) : (
            <span className="cover--empty" />
          )}
          <span className="row__cover-overlay">
            {isSelected ? <PauseIcon size={16} /> : <PlayIcon size={16} />}
          </span>
        </span>

        <span className="row__meta">
          <span className="row__title">
            {track.name}
            {track.explicit && (
              <span className="row__explicit" title="Explicit content">
                E
              </span>
            )}
          </span>
          <span className="row__artists">{track.artists}</span>
        </span>

        <span className="row__album">{track.album}</span>

        <span className="row__timing">
          <time dateTime={play.played_at} title={new Date(play.played_at).toLocaleString("en-US")}>
            {timeOfDay(play.played_at)}
          </time>
          {relative && <span className="row__relative">{relative}</span>}
        </span>

        {track.duration_ms && <span className="row__duration">{duration(track.duration_ms)}</span>}
      </button>

      <a
        className="row__external"
        href={track.spotify_url}
        target="_blank"
        rel="noreferrer noopener"
        title="Open in Spotify"
        aria-label={`Open ${track.name} in Spotify`}
      >
        <ExternalIcon size={15} />
      </a>
    </li>
  )
}
