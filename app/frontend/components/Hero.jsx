import { PlayIcon, ShuffleIcon } from "./icons"
import emblemUrl from "../images/logo.svg"

export default function Hero({ account, visibleCount, onPlayLatest, onShuffle }) {
  const owner = account?.display_name

  return (
    <section className="hero">
      <img className="hero__art" src={emblemUrl} alt="" />

      <div className="hero__body">
        <p className="hero__eyebrow">Spotify · Listening history</p>
        <h1 className="hero__title">DekSlayer&apos;s Latest Activity</h1>

        <p className="hero__lead">
          {owner
            ? `Every track ${owner} plays lands here, newest first.`
            : "Every track played lands here, newest first."}
          <br />
          {visibleCount > 0
            ? `${visibleCount.toLocaleString("en-US")} in view — click any one to listen.`
            : "Nothing in view yet — widen the range or clear the search."}
        </p>

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
