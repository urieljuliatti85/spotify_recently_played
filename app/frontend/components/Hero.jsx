import { PlayIcon, ShuffleIcon } from "./icons"
import { ListenerAvatar } from "./Listener"
import emblemUrl from "../images/logo.svg"

// Who the page is about right now: one listener when the feed is filtered,
// otherwise the owner and however many friends have joined them.
function describe(listeners, selected) {
  if (selected) return `Every track ${selected.name} plays lands here, newest first.`

  const owner = listeners.find((listener) => listener.owner) ?? listeners[0]
  const friends = listeners.length - (owner ? 1 : 0)

  if (!owner) return "Every track played lands here, newest first."
  if (friends === 0) return `Every track ${owner.name} plays lands here, newest first.`

  return `Every track ${owner.name} and ${friends === 1 ? "a friend" : `${friends} friends`} play lands here, newest first.`
}

export default function Hero({ listeners = [], selectedListener, visibleCount, onPlayLatest, onShuffle }) {
  const owner = listeners.find((listener) => listener.owner) ?? listeners[0]

  return (
    <section className="hero">
      <img className="hero__art" src={emblemUrl} alt="" />

      <div className="hero__body">
        <p className="hero__eyebrow">Spotify · Listening history</p>
        <h1 className="hero__title">SpotPlayer&apos;s Latest Activity</h1>

        <p className="hero__lead">
          {describe(listeners, selectedListener)}
          <br />
          {visibleCount > 0
            ? `${visibleCount.toLocaleString("en-US")} in view — click any one to listen.`
            : "Nothing in view yet — widen the range or clear the search."}
        </p>

        {owner && (
          <a
            className="hero__profile"
            href={owner.spotify_url}
            target="_blank"
            rel="noreferrer noopener"
          >
            <ListenerAvatar listener={owner} size={42} />
            <span className="hero__profile-meta">
              <span className="hero__profile-label">Spotify profile</span>
              <strong>{owner.name}</strong>
            </span>
          </a>
        )}

        <div className="hero__actions">
          <button
            type="button"
            className="btn btn--filled"
            onClick={onPlayLatest}
            disabled={visibleCount === 0}
          >
            <PlayIcon size={16} />
            Play latest
          </button>

          <button
            type="button"
            className="btn btn--outline"
            onClick={onShuffle}
            disabled={visibleCount === 0}
          >
            <ShuffleIcon size={16} />
            Shuffle
          </button>
        </div>
      </div>
    </section>
  )
}
