import { useEffect, useMemo, useState } from "react"
import { createUnheardPlaylist, fetchUnheardTracks, searchPlaylistTracks } from "../lib/api"
import { duration } from "../lib/format"
import { ChevronLeftIcon, ExternalIcon } from "./icons"

// Spotify accepts 100 items per add request, and the server caps the selection
// at the same number. Enforcing it here too is what keeps the count under the
// submit button honest.
const MAX_TRACKS = 100

const today = () =>
  new Date().toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" })

export default function UnheardComposer({ connectPath, onClose, onCreated }) {
  const [state, setState] = useState("loading")
  const [error, setError] = useState(null)
  const [tracks, setTracks] = useState([])
  const [chosen, setChosen] = useState(() => new Set())
  const [name, setName] = useState(() => `Never played · ${today()}`)
  const [created, setCreated] = useState(null)
  const [search, setSearch] = useState("")
  const [searchTracks, setSearchTracks] = useState([])
  const [searchState, setSearchState] = useState("idle")

  useEffect(() => {
    const controller = new AbortController()

    fetchUnheardTracks({ signal: controller.signal })
      .then(({ tracks: result }) => {
        const list = result ?? []
        setTracks(list)
        // Everything on by default: the list is already the answer to "what
        // haven't I heard", so the common case is keeping it, not building it.
        setChosen(new Set(list.slice(0, MAX_TRACKS).map((track) => track.spotify_id)))
        setState("ready")
      })
      .catch((cause) => {
        if (controller.signal.aborted) return
        setError(cause)
        setState("error")
      })

    return () => controller.abort()
  }, [])

  useEffect(() => {
    const query = search.trim()
    if (!query) {
      setSearchTracks([])
      setSearchState("idle")
      return undefined
    }

    const controller = new AbortController()
    const timer = setTimeout(() => {
      setSearchState("loading")
      searchPlaylistTracks(query, { signal: controller.signal })
        .then(({ tracks: result }) => {
          setSearchTracks(result ?? [])
          setSearchState("ready")
        })
        .catch((cause) => {
          if (controller.signal.aborted) return
          setError(cause)
          setSearchState("error")
        })
    }, 300)

    return () => {
      clearTimeout(timer)
      controller.abort()
    }
  }, [search])

  // Grouped by the artist that suggested it, because a flat list of eighty
  // tracks gives no way to drop one band's worth in a single pass.
  const groups = useMemo(() => {
    const byArtist = new Map()
    for (const track of tracks) {
      const key = track.from?.id ?? track.artists
      const group = byArtist.get(key) ?? { key, name: track.from?.name ?? track.artists, tracks: [] }
      group.tracks.push(track)
      byArtist.set(key, group)
    }
    return [...byArtist.values()]
  }, [tracks])

  function toggle(id) {
    setChosen((current) => {
      const next = new Set(current)
      if (!next.delete(id)) next.add(id)
      return next
    })
  }

  function toggleGroup(group) {
    const ids = group.tracks.map((track) => track.spotify_id)
    const allOn = ids.every((id) => chosen.has(id))
    setChosen((current) => {
      const next = new Set(current)
      ids.forEach((id) => (allOn ? next.delete(id) : next.add(id)))
      return next
    })
  }

  function submit(event) {
    event.preventDefault()
    if (chosen.size === 0 || chosen.size > MAX_TRACKS) return

    setState("saving")
    setError(null)
    const allTracks = [...tracks, ...searchTracks].filter(
      (track, index, list) => list.findIndex((candidate) => candidate.spotify_id === track.spotify_id) === index
    )
    createUnheardPlaylist({
      name,
      trackIds: allTracks.filter((track) => chosen.has(track.spotify_id)).map((track) => track.spotify_id),
    })
      .then(({ playlist }) => {
        setCreated(playlist)
        setState("created")
        onCreated?.()
      })
      .catch((cause) => {
        // Back to "ready", not "error": the selection is still good and the
        // whole point is that they can fix the name and try again.
        setError(cause)
        setState("ready")
      })
  }

  const back = (
    <button type="button" className="btn btn--ghost playlist-tracks__back" onClick={onClose}>
      <ChevronLeftIcon size={16} />
      All playlists
    </button>
  )

  if (state === "created") {
    return (
      <section className="composer">
        {back}
        <div className="notice">
          <h2>{created?.name} is on Spotify</h2>
          <p className="section__hint">{created?.tracks_count} tracks you had never played.</p>
          {created?.spotify_url && (
            <a className="btn btn--outline" href={created.spotify_url} target="_blank" rel="noreferrer noopener">
              Open in Spotify <ExternalIcon size={14} />
            </a>
          )}
        </div>
      </section>
    )
  }

  if (state === "error") {
    return (
      <section className="composer">
        {back}
        <div className="notice notice--warning">
          <h2>Couldn&apos;t work out what you haven&apos;t heard</h2>
          <p>{error?.message}</p>
          {connectPath && <a className="btn btn--outline" href={connectPath}>Reconnect Spotify</a>}
        </div>
      </section>
    )
  }

  return (
    <form className="composer" onSubmit={submit}>
      {back}
      <header className="section__head">
        <div>
          <h1 className="section__title">Never played</h1>
          <p className="section__hint">
            Tracks by the artists on this feed that nobody here has played. Uncheck what you don&apos;t
            want, then create the playlist.
          </p>
        </div>
      </header>

      <label className="composer__name composer__search">
        <span className="composer__label">Search artists or tracks</span>
        <input
          type="search"
          value={search}
          placeholder="Search Spotify…"
          onChange={(event) => setSearch(event.target.value)}
        />
      </label>

      {searchState === "loading" && <p className="section__hint">Searching Spotify…</p>}
      {searchState === "error" && <p className="composer__error">{error?.message}</p>}
      {searchState === "ready" && searchTracks.length === 0 && (
        <p className="section__hint">No Spotify tracks found.</p>
      )}
      {searchTracks.length > 0 && (
        <section className="composer__search-results">
          <h2 className="section__title">Search results</h2>
          <ul className="composer__list">
            {searchTracks.map((track) => (
              <li key={track.spotify_id}>
                <label className="composer__track">
                  <input
                    type="checkbox"
                    checked={chosen.has(track.spotify_id)}
                    onChange={() => toggle(track.spotify_id)}
                  />
                  <span className="composer__track-cover">
                    {track.album_image_url ? <img src={track.album_image_url} alt="" width="36" height="36" /> : <span className="cover--empty" />}
                  </span>
                  <span className="composer__track-meta">
                    <span className="composer__track-title">{track.name}</span>
                    <span className="composer__track-album">{track.artists} · {track.album}</span>
                  </span>
                </label>
              </li>
            ))}
          </ul>
        </section>
      )}

      {state === "loading" && <p className="section__hint">Asking Spotify about your artists…</p>}

      {state !== "loading" && tracks.length === 0 && searchTracks.length === 0 && (
        <p className="section__hint">Nothing new turned up — this feed has played everything Spotify offered.</p>
      )}

      {(tracks.length > 0 || searchTracks.length > 0) && (
        <>
          <label className="composer__name">
            <span className="composer__label">Playlist name</span>
            <input
              type="text"
              value={name}
              maxLength={100}
              onChange={(event) => setName(event.target.value)}
              required
            />
          </label>

          {error && (
            <div className="composer__error">
              <p>{error.message}</p>
              {connectPath && error.message.includes("playlist-modify-public") && (
                <a href={connectPath}>Reconnect Spotify to grant playlist access</a>
              )}
            </div>
          )}

          <div className="composer__groups">
            {groups.map((group) => (
              <section key={group.key} className="composer__group">
                <button type="button" className="composer__group-head" onClick={() => toggleGroup(group)}>
                  {group.name}
                  <span className="composer__group-count">{group.tracks.length}</span>
                </button>
                <ul className="composer__list">
                  {group.tracks.map((track) => (
                    <li key={track.spotify_id}>
                      <label className="composer__track">
                        <input
                          type="checkbox"
                          checked={chosen.has(track.spotify_id)}
                          onChange={() => toggle(track.spotify_id)}
                        />
                        <span className="composer__track-cover">
                          {track.album_image_url ? (
                            <img src={track.album_image_url} alt="" loading="lazy" width="36" height="36" />
                          ) : (
                            <span className="cover--empty" />
                          )}
                        </span>
                        <span className="composer__track-meta">
                          <span className="composer__track-title">{track.name}</span>
                          <span className="composer__track-album">{track.album}</span>
                        </span>
                        {track.duration_ms && (
                          <span className="ranking__duration">{duration(track.duration_ms)}</span>
                        )}
                      </label>
                    </li>
                  ))}
                </ul>
              </section>
            ))}
          </div>

          <footer className="composer__foot">
            <p className="section__hint">
              {chosen.size} of {[...tracks, ...searchTracks].filter((track, index, list) => list.findIndex((candidate) => candidate.spotify_id === track.spotify_id) === index).length} selected
              {chosen.size > MAX_TRACKS && ` — Spotify takes ${MAX_TRACKS} at a time`}
            </p>
            <button
              type="submit"
              className="btn btn--filled"
              disabled={state === "saving" || chosen.size === 0 || chosen.size > MAX_TRACKS}
            >
              {state === "saving" ? "Creating…" : `Create public playlist (${chosen.size})`}
            </button>
          </footer>
        </>
      )}
    </form>
  )
}
