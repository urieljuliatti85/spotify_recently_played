import { useEffect, useState } from "react"
import { fetchPlaylistTracks, fetchPlaylists } from "../lib/api"
import { duration } from "../lib/format"
import { PlayIcon } from "./icons"

export default function PlaylistView({ onSelect, connectPath }) {
  const [playlists, setPlaylists] = useState([])
  const [selected, setSelected] = useState(null)
  const [tracks, setTracks] = useState([])
  const [state, setState] = useState("loading")
  const [error, setError] = useState(null)

  useEffect(() => {
    const controller = new AbortController()

    fetchPlaylists({ signal: controller.signal })
      .then(({ playlists: result }) => {
        setPlaylists(result ?? [])
        setState("ready")
      })
      .catch((cause) => {
        if (controller.signal.aborted) return
        setError(cause)
        setState("error")
      })

    return () => controller.abort()
  }, [])

  function openPlaylist(playlist) {
    setSelected(playlist)
    setTracks([])
    setState("loading-tracks")

    fetchPlaylistTracks(playlist.id)
      .then(({ tracks: result }) => {
        setTracks(result ?? [])
        setState("tracks-ready")
      })
      .catch((cause) => {
        setError(cause)
        setState("error")
      })
  }

  if (state === "loading") return <p className="section__hint">Loading public playlists…</p>
  if (state === "error" && !selected) {
    return (
      <div className="notice notice--warning">
        <h2>Couldn&apos;t load public playlists</h2>
        <p>{error?.message}</p>
        {connectPath && (
          <a className="btn btn--outline" href={connectPath}>
            Reconnect Spotify
          </a>
        )}
      </div>
    )
  }

  return (
    <section className="section playlists">
      <header className="section__head">
        <div>
          <h1 className="section__title">Public playlists</h1>
          <p className="section__hint">Choose a playlist to play its tracks.</p>
        </div>
      </header>

      {playlists.length === 0 && <p className="section__hint">No public playlists found.</p>}

      <div className="playlist-picker">
        {playlists.map((playlist) => (
          <button
            key={playlist.id}
            type="button"
            className={`playlist-card ${selected?.id === playlist.id ? "playlist-card--selected" : ""}`}
            onClick={() => openPlaylist(playlist)}
          >
            <span className="playlist-card__art">
              {playlist.image_url ? (
                <img src={playlist.image_url} alt="" loading="lazy" width="160" height="160" />
              ) : (
                <span className="cover--empty" />
              )}
            </span>
            <span className="playlist-card__name">{playlist.name}</span>
            <span className="playlist-card__meta">{playlist.tracks_count ?? 0} tracks</span>
          </button>
        ))}
      </div>

      {selected && (
        <div className="playlist-tracks">
          <h2 className="section__title">{selected.name}</h2>
          {state === "loading-tracks" && <p className="section__hint">Loading tracks…</p>}
          {state === "error" && <p className="section__hint">Couldn&apos;t load this playlist.</p>}

          {state === "tracks-ready" && (
            <ol className="ranking">
              {tracks.map((track, index) => (
                <li key={`${selected.id}:${track.spotify_id}`} className="ranking__row">
                  <button
                    type="button"
                    className="ranking__main"
                    onClick={() =>
                      onSelect({
                        id: `playlist:${selected.id}:${track.spotify_id}`,
                        played_at: new Date().toISOString(),
                        track,
                      })
                    }
                    aria-label={`Play ${track.name} by ${track.artists}`}
                  >
                    <span className="ranking__index">{index + 1}</span>
                    <span className="ranking__cover">
                      {track.album_image_url ? (
                        <img src={track.album_image_url} alt="" width="42" height="42" />
                      ) : (
                        <span className="cover--empty" />
                      )}
                      <span className="ranking__cover-overlay">
                        <PlayIcon size={15} />
                      </span>
                    </span>
                    <span className="ranking__meta">
                      <span className="ranking__title">{track.name}</span>
                      <span className="ranking__album">{track.artists}</span>
                    </span>
                    {track.duration_ms && (
                      <span className="ranking__duration">{duration(track.duration_ms)}</span>
                    )}
                  </button>
                </li>
              ))}
            </ol>
          )}
        </div>
      )}
    </section>
  )
}
