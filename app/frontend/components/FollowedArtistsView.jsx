import { useEffect, useState } from "react"
import { fetchFollowedArtists } from "../lib/api"

export default function FollowedArtistsView({ onOpenArtist, connectPath }) {
  const [artists, setArtists] = useState([])
  const [state, setState] = useState("loading")
  const [error, setError] = useState(null)

  useEffect(() => {
    const controller = new AbortController()

    fetchFollowedArtists({ signal: controller.signal })
      .then(({ artists: result }) => {
        setArtists(result ?? [])
        setState("ready")
      })
      .catch((cause) => {
        if (controller.signal.aborted) return
        setError(cause)
        setState("error")
      })

    return () => controller.abort()
  }, [])

  if (state === "loading") return <p className="section__hint">Loading followed artists…</p>

  if (state === "error") {
    return (
      <div className="notice notice--warning">
        <h2>Couldn&apos;t load followed artists</h2>
        <p>{error?.message}</p>
        {error?.status === 403 && connectPath && (
          <a className="btn btn--outline" href={connectPath}>
            Reconnect Spotify
          </a>
        )}
      </div>
    )
  }

  return (
    <section className="section">
      <header className="section__head">
        <div>
          <h1 className="section__title">Followed Artists</h1>
          <p className="section__hint">Who the owner follows on Spotify.</p>
        </div>
      </header>

      {artists.length === 0 && <p className="section__hint">Not following anyone yet.</p>}

      <div className="grid">
        {artists.map((artist) => (
          <button
            key={artist.id}
            type="button"
            className="card card--artist"
            onClick={() => onOpenArtist({ key: artist.id, name: artist.name })}
            aria-label={`Explore ${artist.name}`}
          >
            <span className="card__art card__art--round">
              {artist.image_url ? (
                <img src={artist.image_url} alt="" loading="lazy" width="150" height="150" />
              ) : (
                <span className="cover--empty" />
              )}
            </span>
            <span className="card__name">{artist.name}</span>
            {typeof artist.followers === "number" && (
              <span className="card__sub">{artist.followers.toLocaleString("en-US")} followers</span>
            )}
          </button>
        ))}
      </div>
    </section>
  )
}
