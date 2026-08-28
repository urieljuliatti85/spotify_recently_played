import { useEffect, useState } from "react"
import { fetchTopItems } from "../lib/api"
import { Shelf } from "./Shelf"
import { PlayIcon } from "./icons"

// Spotify's own algorithmic picks for the owner (GET /v1/me/top/{type}) —
// distinct from the "Top Artists" shelf below, which only ever reflects
// plays this app has actually synced. Quiet by design: nothing here is worth
// a page-wide error on the tab everyone lands on first.
export default function TopItemsBox({ onSelect, onOpenArtist, connectPath }) {
  const [artists, setArtists] = useState([])
  const [tracks, setTracks] = useState([])
  const [state, setState] = useState("loading")
  const [error, setError] = useState(null)

  useEffect(() => {
    const controller = new AbortController()

    fetchTopItems({ signal: controller.signal })
      .then(({ artists: topArtists, tracks: topTracks }) => {
        setArtists(topArtists ?? [])
        setTracks(topTracks ?? [])
        setState("ready")
      })
      .catch((cause) => {
        if (controller.signal.aborted) return
        setError(cause)
        setState("error")
      })

    return () => controller.abort()
  }, [])

  if (state === "loading") return null

  // A 403 means the owner's token predates user-top-read — worth a nudge to
  // reconnect. Anything else (never connected, a Spotify outage) is quiet:
  // SetupNotice already covers the first, and there is nothing to do about
  // the second on the tab everyone lands on first.
  if (state === "error") {
    if (error?.status !== 403) return null

    return (
      <section className="section">
        <h2 className="section__title">DekSlayer&apos;s Top Items</h2>
        <p className="section__hint">
          Spotify top items permission is missing.
          {connectPath && <> <a href={connectPath}>Reconnect Spotify</a> to grant it.</>}
        </p>
      </section>
    )
  }

  if (artists.length === 0 && tracks.length === 0) return null

  return (
    <section className="section">
      <h2 className="section__title">DekSlayer&apos;s Top Items</h2>
      <p className="section__hint">Spotify's own picks — not just what made it into this feed.</p>

      {artists.length > 0 && (
        <Shelf title="Top Artists">
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
            </button>
          ))}
        </Shelf>
      )}

      {tracks.length > 0 && (
        <Shelf title="Top Tracks">
          {tracks.map((track, index) => {
            const play = {
              id: `top-track:${index}:${track.spotify_id}`,
              played_at: new Date().toISOString(),
              track,
            }

            return (
              <button
                key={track.spotify_id}
                type="button"
                className="card card--album"
                onClick={() => onSelect(play)}
                title={`Play ${track.name}`}
              >
                <span className="card__art">
                  {track.album_image_url ? (
                    <img src={track.album_image_url} alt="" loading="lazy" width="208" height="208" />
                  ) : (
                    <span className="cover--empty" />
                  )}
                  <span className="card__badge">
                    <PlayIcon size={16} />
                  </span>
                </span>
                <span className="card__name">{track.name}</span>
                <span className="card__sub">{track.artists}</span>
              </button>
            )
          })}
        </Shelf>
      )}
    </section>
  )
}
