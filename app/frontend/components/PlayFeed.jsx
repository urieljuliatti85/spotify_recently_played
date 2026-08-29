import { useEffect, useState } from "react"
import { fetchYoutubeMatches } from "../lib/api"
import { plural } from "../lib/derive"
import { groupByDay } from "../lib/format"
import PlayRow from "./PlayRow"

export default function PlayFeed({
  plays,
  selectedPlayId,
  onSelect,
  onOpenArtist,
  showListener,
  onPickListener,
  hasMore,
  loadingMore,
  onLoadMore,
}) {
  const groups = groupByDay(plays)

  // Keyed by track, not by play: the feed is full of repeats, and a track
  // asked about once stays known for every other row it turns up in. The
  // backend caches the actual YouTube search — this just avoids asking about
  // the same id twice from the same page.
  const [youtubeUrls, setYoutubeUrls] = useState({})

  useEffect(() => {
    const ids = [...new Set(plays.map((play) => play.track.spotify_id))].filter(
      (id) => !(id in youtubeUrls)
    )
    if (ids.length === 0) return undefined

    const controller = new AbortController()
    fetchYoutubeMatches(ids, { signal: controller.signal })
      .then(({ matches }) => {
        // An id present in `matches` was actually resolved (a url, or null
        // for "checked, no clip"); one the backend's per-request cap left out
        // stays absent here too, so the next poll's ids list picks it up
        // again instead of it reading as permanently unknown.
        setYoutubeUrls((current) => ({ ...current, ...matches }))
      })
      .catch(() => {})

    return () => controller.abort()
  }, [plays])

  return (
    <div className="feed">
      {groups.map((group) => (
        <section className="feed__day" key={group.key}>
          <header className="feed__day-head">
            <h3 className="feed__day-label">{group.label}</h3>
            <span className="feed__day-count">{plural(group.plays.length, "track")}</span>
          </header>

          <ul className="feed__list">
            {group.plays.map((play, index) => (
              <PlayRow
                key={play.id}
                play={play}
                index={index}
                isSelected={play.id === selectedPlayId}
                onSelect={onSelect}
                onOpenArtist={onOpenArtist}
                showListener={showListener}
                onPickListener={onPickListener}
                youtubeUrl={youtubeUrls[play.track.spotify_id]}
              />
            ))}
          </ul>
        </section>
      ))}

      {hasMore && (
        <button type="button" className="btn btn--ghost feed__more" onClick={onLoadMore} disabled={loadingMore}>
          {loadingMore ? "Loading…" : "Load more"}
        </button>
      )}
    </div>
  )
}
