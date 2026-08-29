import { useEffect, useState } from "react"
import { searchCatalog } from "../lib/api"
import { duration } from "../lib/format"
import { PlayIcon } from "./icons"
import { Shelf } from "./Shelf"

// Spotify's catalogue, not this feed's history: the search box above this
// narrows the plays already in memory (lib/derive.js#matching, free,
// instant); this reaches for tracks and albums nobody here has played yet.
// Debounced and length-gated because every request spends the owner's
// Spotify quota, the same request Api::SearchController spends on the
// caller's behalf.
const MIN_QUERY_LENGTH = 2
const DEBOUNCE_MS = 350

export default function CatalogSearch({ query, onSelectTrack, onOpenAlbum }) {
  const [state, setState] = useState("idle")
  const [tracks, setTracks] = useState([])
  const [albums, setAlbums] = useState([])

  useEffect(() => {
    const trimmed = query.trim()
    if (trimmed.length < MIN_QUERY_LENGTH) {
      setState("idle")
      setTracks([])
      setAlbums([])
      return undefined
    }

    const controller = new AbortController()
    const timer = setTimeout(() => {
      setState("loading")
      searchCatalog(trimmed, { signal: controller.signal })
        .then(({ tracks: foundTracks, albums: foundAlbums }) => {
          setTracks(foundTracks ?? [])
          setAlbums(foundAlbums ?? [])
          setState("ready")
        })
        .catch((cause) => {
          if (controller.signal.aborted) return
          setState("error")
        })
    }, DEBOUNCE_MS)

    return () => {
      clearTimeout(timer)
      controller.abort()
    }
  }, [query])

  if (state === "idle") return null
  if (state === "ready" && tracks.length === 0 && albums.length === 0) return null

  return (
    <>
      {state === "loading" && <p className="section__hint">Searching Spotify’s catalogue…</p>}
      {state === "error" && <p className="section__hint">Couldn’t search Spotify’s catalogue.</p>}

      {tracks.length > 0 && (
        <section className="section catalog-search">
          <h2 className="section__title">Not heard here yet</h2>
          <p className="section__hint">Tracks from Spotify’s catalogue this feed hasn’t played.</p>

          <ol className="ranking">
            {tracks.map((track, index) => (
              <li key={track.spotify_id} className="ranking__row">
                <button
                  type="button"
                  className="ranking__main"
                  onClick={() =>
                    onSelectTrack({
                      id: `catalog:${track.spotify_id}`,
                      played_at: new Date().toISOString(),
                      track,
                    })
                  }
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
                  {track.duration_ms && <span className="ranking__duration">{duration(track.duration_ms)}</span>}
                </button>
              </li>
            ))}
          </ol>
        </section>
      )}

      {albums.length > 0 && (
        <Shelf title="Albums not heard here yet">
          {albums.map((album) => (
            <button
              key={album.spotify_id}
              type="button"
              className="card card--album"
              onClick={() => onOpenAlbum(album.spotify_id)}
              title={`Open ${album.name}`}
            >
              <span className="card__art">
                {album.image_url ? (
                  <img src={album.image_url} alt="" loading="lazy" width="208" height="208" />
                ) : (
                  <span className="cover--empty" />
                )}
              </span>
              <span className="card__name">{album.name}</span>
              <span className="card__sub">{album.artists}</span>
            </button>
          ))}
        </Shelf>
      )}
    </>
  )
}
