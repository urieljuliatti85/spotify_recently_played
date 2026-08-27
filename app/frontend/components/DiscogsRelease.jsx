import { useEffect, useMemo, useState } from "react"
import { fetchDiscogsRelease } from "../lib/api"
import { duration as formatDuration } from "../lib/format"
import { ChevronLeftIcon, DiscIcon, ExternalIcon, PlayIcon } from "./icons"

// Headings and index rows exist to structure a vinyl side; they name nothing
// playable, so they are printed as dividers rather than as tracks.
const DIVIDERS = new Set(["heading", "index"])

function plays(tracks, discogsId) {
  return tracks
    .filter((row) => row.playable && row.track)
    .map((row) => ({
      id: `discogs:${discogsId}:${row.position || row.title}:${row.track.spotify_id}`,
      played_at: new Date().toISOString(),
      track: row.track,
    }))
}

export default function DiscogsRelease({ discogsId, onBack, onSelect, selectedPlayId }) {
  const [data, setData] = useState(null)
  const [state, setState] = useState("loading")
  const [error, setError] = useState(null)

  useEffect(() => {
    const controller = new AbortController()
    setState("loading")

    fetchDiscogsRelease(discogsId, { signal: controller.signal })
      .then((payload) => {
        setData(payload)
        setState("ready")
      })
      .catch((cause) => {
        if (controller.signal.aborted) return
        setError(cause)
        setState("error")
      })

    return () => controller.abort()
  }, [discogsId])

  const tracks = data?.tracks ?? []
  const queue = useMemo(() => plays(tracks, discogsId), [tracks, discogsId])

  if (state === "loading") {
    return (
      <section className="section discogs-detail">
        <BackLink onBack={onBack} />
        <p className="section__hint">Matching this record against Spotify…</p>
      </section>
    )
  }

  if (state === "error") {
    return (
      <section className="section discogs-detail">
        <BackLink onBack={onBack} />
        <div className="notice notice--warning">
          <h2>Couldn&apos;t open this record</h2>
          <p>{error?.message}</p>
        </div>
      </section>
    )
  }

  const { release, spotify } = data
  const playable = queue.length

  return (
    <section className="section discogs-detail">
      <BackLink onBack={onBack} />

      <header className="discogs-detail__head">
        <div className="discogs-detail__art">
          {release.cover_url ? (
            <img src={release.cover_url} alt="" width="260" height="260" />
          ) : (
            <span className="cover--empty" />
          )}
        </div>

        <div className="discogs-detail__meta">
          <p className="discogs-detail__artist">{release.artist}</p>
          <h1 className="discogs-detail__title">{release.title}</h1>

          <p className="discogs-detail__facts">
            {[release.year, release.format_summary, release.label, release.catno, release.country]
              .filter(Boolean)
              .join(" · ")}
          </p>

          {(release.genres?.length > 0 || release.styles?.length > 0) && (
            <ul className="discogs-tags">
              {[...(release.genres ?? []), ...(release.styles ?? [])].map((tag) => (
                <li key={tag}>{tag}</li>
              ))}
            </ul>
          )}

          <p className="discogs-detail__spotify">
            <MatchSummary spotify={spotify} playable={playable} total={tracks.length} />
          </p>

          <div className="discogs-detail__actions">
            <button
              type="button"
              className="btn btn--filled"
              onClick={() => queue[0] && onSelect(queue[0], null, queue)}
              disabled={playable === 0}
            >
              <PlayIcon size={15} />
              {playable > 0 ? "Play album" : "Nothing to play"}
            </button>

            {release.discogs_url && (
              <a className="btn btn--outline" href={release.discogs_url} target="_blank" rel="noreferrer">
                <DiscIcon size={15} />
                Discogs
              </a>
            )}

            {spotify.album?.spotify_url && (
              <a
                className="btn btn--outline"
                href={spotify.album.spotify_url}
                target="_blank"
                rel="noreferrer"
              >
                <ExternalIcon size={15} />
                Spotify
              </a>
            )}
          </div>
        </div>
      </header>

      {tracks.length === 0 && (
        <p className="section__hint">
          Discogs has no tracklist for this pressing, so there is nothing to match.
        </p>
      )}

      <ol className="discogs-tracks">
        {tracks.map((row, index) => {
          if (DIVIDERS.has(row.type)) {
            return (
              <li key={`divider-${index}`} className="discogs-tracks__divider">
                {row.title}
              </li>
            )
          }

          const play = queue.find((candidate) => candidate.track.spotify_id === row.track?.spotify_id)
          const isSelected = play && play.id === selectedPlayId

          return (
            <li
              key={`${row.position}-${index}`}
              className={`discogs-track ${row.playable ? "" : "discogs-track--absent"} ${
                isSelected ? "discogs-track--selected" : ""
              }`}
            >
              <button
                type="button"
                className="discogs-track__main"
                onClick={() => play && onSelect(play, null, queue)}
                disabled={!play}
                title={play ? `Play ${row.title}` : "Not on Spotify"}
              >
                <span className="discogs-track__position">{row.position || index + 1}</span>

                <span className="discogs-track__badge">
                  <PlayIcon size={13} />
                </span>

                <span className="discogs-track__meta">
                  <span className="discogs-track__title">{row.title}</span>
                  {row.artists && <span className="discogs-track__artists">{row.artists}</span>}
                </span>

                <span className="discogs-track__note">
                  {row.playable ? (
                    // Worth saying out loud: this row is a different record
                    // from the one on the shelf, found by title.
                    row.source === "search" && <em>elsewhere on Spotify</em>
                  ) : (
                    <em>not on Spotify</em>
                  )}
                </span>

                <span className="discogs-track__duration">
                  {row.duration || formatDuration(row.track?.duration_ms) || ""}
                </span>
              </button>
            </li>
          )
        })}
      </ol>
    </section>
  )
}

function BackLink({ onBack }) {
  return (
    <button type="button" className="btn btn--ghost discogs-detail__back" onClick={onBack}>
      <ChevronLeftIcon size={16} />
      All records
    </button>
  )
}

// The one sentence that explains a half-matched record, which is the normal
// case for a pressing that Spotify only carries in part.
function MatchSummary({ spotify, playable, total }) {
  if (spotify.error) return <span className="discogs-detail__warn">{spotify.error}</span>
  if (total === 0) return null

  if (playable === 0) {
    return <span className="discogs-detail__warn">None of these tracks are on Spotify.</span>
  }

  return (
    <>
      <strong>
        {playable} of {total}
      </strong>{" "}
      {playable === total ? "tracks are on Spotify" : "tracks found on Spotify"}
      {spotify.album?.name && (
        <>
          {" — matched to "}
          <span className="discogs-detail__album">{spotify.album.name}</span>
        </>
      )}
      {spotify.market && <span className="discogs-detail__market"> ({spotify.market})</span>}
    </>
  )
}
