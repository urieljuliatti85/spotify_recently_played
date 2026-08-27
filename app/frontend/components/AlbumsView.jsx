import { useEffect, useState } from "react"
import { fetchAlbumDiscogs, fetchAlbumReleases, fetchAlbumTracks } from "../lib/api"
import { duration } from "../lib/format"
import { ChevronLeftIcon, PlayIcon } from "./icons"

export default function AlbumsView({ albums, onSelect }) {
  const [selected, setSelected] = useState(null)
  const [tracks, setTracks] = useState([])
  const [state, setState] = useState("ready")
  const [error, setError] = useState(null)
  const [discogsUrls, setDiscogsUrls] = useState({})
  const [releases, setReleases] = useState([])
  const [releasesState, setReleasesState] = useState("idle")
  const [releasesError, setReleasesError] = useState(null)

  useEffect(() => {
    const albumsWithIds = albums.filter((album) => album.albumId)
    if (albumsWithIds.length === 0) return undefined

    const controller = new AbortController()
    Promise.all(
      albumsWithIds.map((album) =>
        fetchAlbumDiscogs(album.albumId, { signal: controller.signal }).then(({ url }) => [album.key, url])
      )
    )
      .then((results) => setDiscogsUrls(Object.fromEntries(results.filter(([, url]) => url))))
      .catch(() => {})

    return () => controller.abort()
  }, [albums])

  function openAlbum(album) {
    setSelected(album)
    setError(null)
    setReleases([])
    setReleasesError(null)
    setReleasesState("loading")
    fetchAlbumReleases({ title: album.name, artist: album.artists })
      .then(({ releases: result }) => {
        setReleases(result ?? [])
        setReleasesState("ready")
      })
      .catch((cause) => {
        setReleasesError(cause)
        setReleasesState("error")
      })

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
          <ChevronLeftIcon size={16} /> Albums
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
            <p className="albums__eyebrow">Album</p>
            <h1 className="section__title">{selected.name}</h1>
            <p className="section__hint">{selected.artists}</p>
          </div>
        </header>
        {state === "loading" && <p className="section__hint">Loading tracks…</p>}
        {state === "error" && <p className="section__hint">{error?.message || "Couldn't load the tracks."}</p>}
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
        {releasesState === "loading" && (
          <section className="albums__releases">
            <h2 className="section__title">Releases on Discogs</h2>
            <p className="section__hint">Loading releases…</p>
          </section>
        )}
        {releasesState === "error" && (
          <section className="albums__releases">
            <h2 className="section__title">Releases on Discogs</h2>
            <p className="section__hint">
              {releasesError?.message || "Couldn't load releases from the Discogs Shelf."}
            </p>
          </section>
        )}
        {releasesState === "ready" && releases.length > 0 && (
          <section className="albums__releases">
            <h2 className="section__title">Releases on Discogs</h2>
            <div className="albums__release-list">
              {releases.map((release) => (
                <a
                  key={release.discogs_id}
                  className="albums__release"
                  href={
                    release.marketplace?.album?.url ||
                    release.marketplace?.marketplace_url ||
                    release.marketplace_url ||
                    release.discogs_url
                  }
                  target="_blank"
                  rel="noreferrer noopener"
                >
                  <strong>{release.title}</strong>
                  <span>{[release.year, release.format_summary, release.country].filter(Boolean).join(" · ")}</span>
                </a>
              ))}
            </div>
          </section>
        )}
        {releasesState === "ready" && releases.length === 0 && (
          <section className="albums__releases">
            <h2 className="section__title">Releases on Discogs</h2>
            <p className="section__hint">No matching releases were found in the Discogs Shelf.</p>
          </section>
        )}
      </section>
    )
  }

  return (
    <section className="section albums">
      <header className="section__head">
        <div>
          <h1 className="section__title">Albums</h1>
          <p className="section__hint">Your recently played albums.</p>
        </div>
      </header>
      <div className="grid">
        {albums.map((album) => (
          <article key={album.key} className="card card--album">
            <button type="button" className="card__open" onClick={() => openAlbum(album)}>
            <span className="card__art">
              {album.imageUrl ? <img src={album.imageUrl} alt="" loading="lazy" width="208" height="208" /> : <span className="cover--empty" />}
            </span>
            <span className="card__name">{album.name}</span>
            <span className="card__sub">{album.artists}</span>
            </button>
            {discogsUrls[album.key] && (
              <a
                className="btn btn--outline albums__buy"
                href={discogsUrls[album.key]}
                target="_blank"
                rel="noreferrer noopener"
              >
                Buy this album
              </a>
            )}
          </article>
        ))}
        {albums.length === 0 && <p className="section__hint">No albums found.</p>}
      </div>
    </section>
  )
}
