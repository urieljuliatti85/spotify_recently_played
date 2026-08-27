import { useEffect, useState } from "react"
import { fetchPlaylistTracks, fetchPlaylists } from "../lib/api"
import { duration } from "../lib/format"
import { ChevronLeftIcon, PlayIcon, SparkIcon } from "./icons"
import UnheardComposer from "./UnheardComposer"

export default function PlaylistView({ onSelect, connectPath }) {
  const [playlists, setPlaylists] = useState([])
  const [selected, setSelected] = useState(null)
  const [tracks, setTracks] = useState([])
  const [state, setState] = useState("loading")
  const [error, setError] = useState(null)
  const [composing, setComposing] = useState(false)
  // Bumped after a playlist is created, to re-run the fetch below. The server
  // drops its own five-minute cache on create, so this is all that stands
  // between the new playlist and the grid.
  const [reload, setReload] = useState(0)

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
  }, [reload])

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

  const playlistPlays = tracks.map((track, index) => ({
      id: `playlist:${selected?.id}:${index}:${track.spotify_id}`,
      played_at: new Date().toISOString(),
      track,
  }))

  // Ahead of the two returns below on purpose: what the owner has never played
  // is worked out from the feed and from Spotify's catalogue, so the composer
  // still works on a day the playlists themselves will not load.
  if (composing) {
    return (
      <section className="section playlists">
        <UnheardComposer
          connectPath={connectPath}
          onClose={() => setComposing(false)}
          onCreated={() => setReload((n) => n + 1)}
        />
      </section>
    )
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
        <button type="button" className="btn btn--filled" onClick={() => setComposing(true)}>
          <SparkIcon size={16} /> Add new playlist
        </button>
      </div>
    )
  }

  return (
    <section className="section playlists">
      {!selected && (
        <>
          <header className="section__head">
            <div>
              <h1 className="section__title">Public playlists</h1>
              <p className="section__hint">Choose a playlist to play its tracks.</p>
            </div>
            <button type="button" className="btn btn--filled" onClick={() => setComposing(true)}>
              <SparkIcon size={16} /> Add new playlist
            </button>
          </header>

          {playlists.length === 0 && <p className="section__hint">No public playlists found.</p>}

          <div className="playlist-picker">
            {playlists.map((playlist) => (
              <button
                key={playlist.id}
                type="button"
                className="playlist-card"
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
        </>
      )}

      {selected && (
        <div className="playlist-tracks">
          <div className="playlist-tracks__head">
            <button
              type="button"
              className="btn btn--ghost playlist-tracks__back"
              onClick={() => {
                setSelected(null)
                setTracks([])
                setState("ready")
              }}
            >
              <ChevronLeftIcon size={16} />
              All playlists
            </button>
            <h2 className="section__title">{selected.name}</h2>
          </div>
          {state === "loading-tracks" && <p className="section__hint">Loading tracks…</p>}
          {state === "error" && <p className="section__hint">Couldn&apos;t load this playlist.</p>}

          {state === "tracks-ready" && (
            <ol className="ranking">
              {playlistPlays.map((playlistPlay, index) => (
                <li key={playlistPlay.id} className="ranking__row">
                  <button
                    type="button"
                    className="ranking__main"
                    onClick={() => onSelect(playlistPlay, null, playlistPlays)}
                    aria-label={`Play ${playlistPlay.track.name} by ${playlistPlay.track.artists}`}
                  >
                    <span className="ranking__index">{index + 1}</span>
                    <span className="ranking__cover">
                      {playlistPlay.track.album_image_url ? (
                        <img src={playlistPlay.track.album_image_url} alt="" width="42" height="42" />
                      ) : (
                        <span className="cover--empty" />
                      )}
                      <span className="ranking__cover-overlay">
                        <PlayIcon size={15} />
                      </span>
                    </span>
                    <span className="ranking__meta">
                      <span className="ranking__title">{playlistPlay.track.name}</span>
                      <span className="ranking__album">{playlistPlay.track.artists}</span>
                    </span>
                    {playlistPlay.track.duration_ms && (
                      <span className="ranking__duration">{duration(playlistPlay.track.duration_ms)}</span>
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
