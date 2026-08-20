import { useEffect, useMemo, useState } from "react"
import { fetchArtistTracks } from "../lib/api"
import { plural } from "../lib/derive"
import { dayLabel, duration } from "../lib/format"
import PlayFeed from "./PlayFeed"
import { AlbumCard, Shelf } from "./Shelf"
import { ChevronLeftIcon, PauseIcon, PlayIcon, ShuffleIcon } from "./icons"

export default function ArtistView({ profile, selectedPlayId, onSelect, onBack, onShuffle }) {
  const { name, imageUrl, count, trackCount, albumCount, topTracks, albums, plays } = profile
  const [catalogTracks, setCatalogTracks] = useState([])
  const [catalogState, setCatalogState] = useState("idle")
  const [catalogError, setCatalogError] = useState(null)

  useEffect(() => {
    if (!profile.id) {
      setCatalogTracks([])
      setCatalogState("idle")
      return undefined
    }

    const controller = new AbortController()
    setCatalogState("loading")
    setCatalogError(null)

    fetchArtistTracks(profile.id, { signal: controller.signal })
      .then(({ tracks }) => {
        setCatalogTracks(tracks ?? [])
        setCatalogState("ready")
      })
      .catch((error) => {
        if (controller.signal.aborted) return
        setCatalogError(error)
        setCatalogState("error")
      })

    return () => controller.abort()
  }, [profile.id])

  const playedTrackIds = useMemo(
    () => new Set(plays.map((play) => play.track.spotify_id).filter(Boolean)),
    [plays]
  )
  const otherTracks = catalogTracks.filter((track) => !playedTrackIds.has(track.spotify_id))

  function playCatalogTrack(track) {
    onSelect({
      id: `spotify:${track.spotify_id}`,
      played_at: new Date().toISOString(),
      track,
    })
  }

  return (
    <div className="artist">
      <button type="button" className="backlink" onClick={onBack}>
        <ChevronLeftIcon size={16} />
        Artists
      </button>

      <header className="artist__head">
        <span className="artist__art">
          {imageUrl ? (
            <img src={imageUrl} alt="" width="180" height="180" />
          ) : (
            <span className="cover--empty" />
          )}
        </span>

        <div className="artist__body">
          <p className="artist__eyebrow">Artist</p>
          <h1 className="artist__name">{name}</h1>

          {count > 0 ? (
            <>
              <p className="artist__stats">
                {plural(count, "play")} · {plural(trackCount, "track")} ·{" "}
                {plural(albumCount, "album")}
              </p>

              <p className="artist__since">
                First heard {dayLabel(profile.firstPlayedAt).toLowerCase()}
              </p>

              <div className="artist__actions">
                <button
                  type="button"
                  className="btn btn--filled"
                  onClick={() => onSelect(profile.latestPlay)}
                >
                  <PlayIcon size={16} />
                  Play latest
                </button>

                <button type="button" className="btn btn--outline" onClick={onShuffle}>
                  <ShuffleIcon size={16} />
                  Shuffle
                </button>
              </div>
            </>
          ) : (
            <p className="artist__stats">
              Nothing from {name} in this range. Widen it in the sidebar to see more.
            </p>
          )}
        </div>
      </header>

      {topTracks.length > 0 && (
        <section className="section">
          <h2 className="section__title">Most played</h2>

          <ol className="ranking">
            {topTracks.map((entry, index) => {
              const isSelected = entry.latestPlay.id === selectedPlayId

              return (
                <li
                  key={entry.key}
                  className={`ranking__row ${isSelected ? "ranking__row--selected" : ""}`}
                >
                  <button
                    type="button"
                    className="ranking__main"
                    onClick={() => onSelect(entry.latestPlay)}
                    aria-pressed={isSelected}
                    aria-label={`Play ${entry.track.name}`}
                  >
                    <span className="ranking__index">{index + 1}</span>

                    <span className="ranking__cover">
                      {entry.track.album_image_url ? (
                        <img
                          src={entry.track.album_image_url}
                          alt=""
                          loading="lazy"
                          width="42"
                          height="42"
                        />
                      ) : (
                        <span className="cover--empty" />
                      )}
                      <span className="ranking__cover-overlay">
                        {isSelected ? <PauseIcon size={15} /> : <PlayIcon size={15} />}
                      </span>
                    </span>

                    <span className="ranking__meta">
                      <span className="ranking__title">{entry.track.name}</span>
                      <span className="ranking__album">{entry.track.album}</span>
                    </span>

                    <span className="ranking__count">{plural(entry.count, "play")}</span>

                    {entry.track.duration_ms && (
                      <span className="ranking__duration">{duration(entry.track.duration_ms)}</span>
                    )}
                  </button>
                </li>
              )
            })}
          </ol>
        </section>
      )}

      {profile.id && (catalogState === "loading" || otherTracks.length > 0 || catalogError) && (
        <section className="section">
          <h2 className="section__title">More from {name}</h2>

          {catalogState === "loading" && (
            <p className="section__hint">Loading tracks from Spotify…</p>
          )}

          {catalogState === "error" && (
            <p className="section__hint">Couldn&apos;t load more tracks from Spotify.</p>
          )}

          {catalogState === "ready" && otherTracks.length > 0 && (
            <ol className="ranking">
              {otherTracks.map((track, index) => (
                <li key={track.spotify_id} className="ranking__row">
                  <button
                    type="button"
                    className="ranking__main"
                    onClick={() => playCatalogTrack(track)}
                    aria-label={`Play ${track.name}`}
                  >
                    <span className="ranking__index">{index + 1}</span>
                    <span className="ranking__cover">
                      {track.album_image_url ? (
                        <img
                          src={track.album_image_url}
                          alt=""
                          loading="lazy"
                          width="42"
                          height="42"
                        />
                      ) : (
                        <span className="cover--empty" />
                      )}
                      <span className="ranking__cover-overlay">
                        <PlayIcon size={15} />
                      </span>
                    </span>
                    <span className="ranking__meta">
                      <span className="ranking__title">{track.name}</span>
                      <span className="ranking__album">{track.album}</span>
                    </span>
                    {track.duration_ms && (
                      <span className="ranking__duration">{duration(track.duration_ms)}</span>
                    )}
                  </button>
                </li>
              ))}
            </ol>
          )}
        </section>
      )}

      {albums.length > 0 && (
        <Shelf title="Albums">
          {albums.map((album) => (
            <AlbumCard key={album.key} album={album} onSelect={onSelect} />
          ))}
        </Shelf>
      )}

      {plays.length > 0 && (
        <section className="section">
          <h2 className="section__title">Every play</h2>
          <PlayFeed
            plays={plays}
            selectedPlayId={selectedPlayId}
            onSelect={onSelect}
            hasMore={false}
          />
        </section>
      )}
    </div>
  )
}
