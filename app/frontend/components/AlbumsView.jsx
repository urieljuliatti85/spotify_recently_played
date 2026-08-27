import { useState } from "react"
import { fetchAlbumTracks } from "../lib/api"
import { duration } from "../lib/format"
import { ChevronLeftIcon, PlayIcon } from "./icons"

export default function AlbumsView({ albums, onSelect }) {
  const [selected, setSelected] = useState(null)
  const [tracks, setTracks] = useState([])
  const [state, setState] = useState("ready")
  const [error, setError] = useState(null)

  function openAlbum(album) {
    setSelected(album)
    setError(null)
    if (!album.albumId) {
      const uniqueTracks = new Map(album.plays.map((play) => [play.track.spotify_id, play.track]))
      setTracks([...uniqueTracks.values()])
      setState("ready")
      return
    }

    setState("loading")
    fetchAlbumTracks(album.albumId)
      .then(({ tracks: result }) => {
        setTracks(result ?? [])
        setState("ready")
      })
      .catch((cause) => {
        setError(cause)
        setState("error")
      })
  }

  if (selected) {
    const plays = tracks.map((track, index) => ({
      id: `album:${selected.albumId}:${index}:${track.spotify_id}`,
      played_at: new Date().toISOString(),
      track,
    }))

    return (
      <section className="section albums">
        <button type="button" className="btn btn--ghost" onClick={() => setSelected(null)}>
          <ChevronLeftIcon size={16} /> Albuns
        </button>
        <header className="section__head albums__detail-head">
          <span className="albums__detail-art">
            {selected.imageUrl ? (
              <img src={selected.imageUrl} alt="" width="180" height="180" />
            ) : (
              <span className="cover--empty" />
            )}
          </span>
          <div>
            <p className="albums__eyebrow">Álbum</p>
            <h1 className="section__title">{selected.name}</h1>
            <p className="section__hint">{selected.artists}</p>
          </div>
        </header>
        {state === "loading" && <p className="section__hint">Carregando músicas…</p>}
        {state === "error" && <p className="section__hint">{error?.message || "Não foi possível carregar as músicas."}</p>}
        {state === "ready" && (
          <ol className="ranking">
            {plays.map((play, index) => (
              <li key={play.id} className="ranking__row">
                <button type="button" className="ranking__main" onClick={() => onSelect(play)}>
                  <span className="ranking__index">{index + 1}</span>
                  <span className="ranking__cover">
                    {play.track.album_image_url ? <img src={play.track.album_image_url} alt="" width="42" height="42" /> : <span className="cover--empty" />}
                    <span className="ranking__cover-overlay"><PlayIcon size={15} /></span>
                  </span>
                  <span className="ranking__meta">
                    <span className="ranking__title">{play.track.name}</span>
                    <span className="ranking__album">{play.track.artists}</span>
                  </span>
                  {play.track.duration_ms && <span className="ranking__duration">{duration(play.track.duration_ms)}</span>}
                </button>
              </li>
            ))}
          </ol>
        )}
      </section>
    )
  }

  return (
    <section className="section albums">
      <header className="section__head">
        <div>
          <h1 className="section__title">Albuns</h1>
          <p className="section__hint">Os últimos álbuns ouvidos.</p>
        </div>
      </header>
      <div className="grid">
        {albums.map((album) => (
          <button key={album.key} type="button" className="card card--album" onClick={() => openAlbum(album)}>
            <span className="card__art">
              {album.imageUrl ? <img src={album.imageUrl} alt="" loading="lazy" width="208" height="208" /> : <span className="cover--empty" />}
            </span>
            <span className="card__name">{album.name}</span>
            <span className="card__sub">{album.artists}</span>
          </button>
        ))}
        {albums.length === 0 && <p className="section__hint">Nenhum álbum encontrado.</p>}
      </div>
    </section>
  )
}
