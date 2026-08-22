import { useMemo, useState } from "react"
import { matchingListeners, plural } from "../lib/derive"
import { duration, relativeTime } from "../lib/format"
import { ListenerAvatar } from "./Listener"
import { PlayIcon, SearchIcon } from "./icons"

// One person's card: who they are, what they just played, and what they have
// been playing most in whatever range is selected.
function ListenerCard({ listener, onSelect, onOpenArtist, onOpenFeed, selectedPlayId }) {
  const { latestPlay, topArtists, topTracks, count } = listener
  const relative = latestPlay && relativeTime(latestPlay.played_at)
  // The cards derive from the feed already loaded, which is paginated and
  // ranged. Showing the stored total next to it keeps "0 in view" from reading
  // as "this person has never played anything".
  const total = listener.plays_count ?? count
  const partial = total > count

  return (
    <article className="lcard">
      <header className="lcard__head">
        <ListenerAvatar listener={listener} size={48} />

        <div className="lcard__id">
          <h3 className="lcard__name">
            {listener.name}
            {listener.owner && <span className="listener__badge">owner</span>}
          </h3>
          <p className="lcard__stat">
            {plural(count, "play")} in view
            {partial && <span className="lcard__total"> · {total.toLocaleString("en-US")} stored</span>}
          </p>
        </div>
      </header>

      {latestPlay ? (
        <button
          type="button"
          className={`lcard__now ${latestPlay.id === selectedPlayId ? "lcard__now--playing" : ""}`}
          onClick={() => onSelect(latestPlay, null, listener.plays)}
          aria-label={`Play ${latestPlay.track.name}, the last track ${listener.name} played`}
        >
          <span className="lcard__now-cover">
            {latestPlay.track.album_image_url ? (
              <img src={latestPlay.track.album_image_url} alt="" loading="lazy" width="56" height="56" />
            ) : (
              <span className="cover--empty" />
            )}
            <span className="lcard__now-overlay">
              <PlayIcon size={16} />
            </span>
          </span>

          <span className="lcard__now-meta">
            <span className="lcard__now-label">{relative ?? "Last played"}</span>
            <span className="lcard__now-title">{latestPlay.track.name}</span>
            <span className="lcard__now-artists">{latestPlay.track.artists}</span>
          </span>
        </button>
      ) : (
        <p className="lcard__empty">
          {total > 0 ? "Nothing in this range — widen it to see their history." : "Nothing played yet."}
        </p>
      )}

      {topArtists.length > 0 && (
        <div className="lcard__section">
          <p className="lcard__label">On repeat</p>
          <ul className="lcard__chips">
            {topArtists.map((artist) => (
              <li key={artist.key}>
                <button
                  type="button"
                  className="lcard__chip"
                  onClick={() => onOpenArtist(artist)}
                  aria-label={`Explore ${artist.name}`}
                >
                  {artist.imageUrl ? (
                    <img src={artist.imageUrl} alt="" loading="lazy" width="20" height="20" />
                  ) : (
                    <span className="lcard__chip-blank" aria-hidden="true" />
                  )}
                  {artist.name}
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}

      {topTracks.length > 0 && (
        <div className="lcard__section">
          <p className="lcard__label">Most played</p>
          <ol className="lcard__tracks">
            {topTracks.map((entry, index) => (
              <li key={entry.key}>
                <button
                  type="button"
                  className={`lcard__track ${entry.latestPlay.id === selectedPlayId ? "lcard__track--playing" : ""}`}
                  onClick={() => onSelect(entry.latestPlay, null, listener.plays)}
                  aria-label={`Play ${entry.track.name}`}
                >
                  <span className="lcard__track-index">{index + 1}</span>
                  <span className="lcard__track-name">{entry.track.name}</span>
                  <span className="lcard__track-count">
                    {entry.count > 1 ? `×${entry.count}` : duration(entry.track.duration_ms)}
                  </span>
                </button>
              </li>
            ))}
          </ol>
        </div>
      )}

      <button
        type="button"
        className="btn btn--ghost lcard__more"
        onClick={() => onOpenFeed(listener.id)}
        aria-label={`See every track ${listener.name} played`}
      >
        See all plays
      </button>
    </article>
  )
}

/**
 * The Listeners tab: everyone whose account is linked, side by side.
 *
 * This is the honest population — people who authorized their own account.
 * Spotify has no API for reading a follower's listening, and none for
 * enumerating followers in the first place.
 */
export default function ListenersView({
  listeners,
  onSelect,
  onOpenArtist,
  onOpenFeed,
  selectedPlayId,
  connectPath,
}) {
  // Local to the tab, and deliberately not the top bar's search: that one
  // filters tracks, and a card that vanished because its owner played nothing
  // matching would read as them having left. This filters people by name.
  const [filter, setFilter] = useState("")
  const shown = useMemo(() => matchingListeners(listeners, filter), [listeners, filter])

  if (listeners.length === 0) {
    return (
      <div className="notice">
        <h2>No one is on the feed yet</h2>
        <p>
          Link your own account, then run <code>bin/rails &quot;spotify:invite[Name]&quot;</code> to
          get a single-use link a friend can use to add theirs.
        </p>
        {connectPath && (
          <a className="notice__cta" href={connectPath}>
            Connect Spotify
          </a>
        )}
      </div>
    )
  }

  return (
    <section className="section">
      <header className="section__head">
        <div>
          <h1 className="section__title">Listeners</h1>
          <p className="section__hint">
            {listeners.length === 1
              ? "Just you so far — invite a friend and they show up here."
              : filter
                ? `${shown.length} of ${listeners.length} people.`
                : `${listeners.length} people, and what each of them has been playing.`}
          </p>
        </div>

        {/* Only worth the space once there is a roster to sift through. */}
        {listeners.length > 1 && (
          <label className="search">
            <SearchIcon size={16} />
            <input
              type="search"
              value={filter}
              onChange={(event) => setFilter(event.target.value)}
              placeholder="Filter listeners by name…"
              aria-label="Filter listeners by name"
            />
          </label>
        )}
      </header>

      {shown.length === 0 ? (
        <p className="section__hint">
          Nobody here is called “{filter}”.
        </p>
      ) : (
        <div className="lcards">
          {shown.map((listener) => (
            <ListenerCard
              key={listener.id}
              listener={listener}
              onSelect={onSelect}
              onOpenArtist={onOpenArtist}
              onOpenFeed={onOpenFeed}
              selectedPlayId={selectedPlayId}
            />
          ))}
        </div>
      )}
    </section>
  )
}
