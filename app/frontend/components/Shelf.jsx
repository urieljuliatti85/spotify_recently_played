import { useRef } from "react"
import { plural } from "../lib/derive"
import { ChevronLeftIcon, ChevronRightIcon, PlayIcon } from "./icons"

// Scrolls by just under a full viewport so the card at the edge stays visible
// as an anchor between pages.
const PAGE_RATIO = 0.85

export function Shelf({ title, children }) {
  const trackRef = useRef(null)

  function scrollBy(direction) {
    const track = trackRef.current
    if (!track) return

    track.scrollBy({ left: direction * track.clientWidth * PAGE_RATIO, behavior: "smooth" })
  }

  return (
    <section className="shelf">
      <header className="shelf__head">
        <h2 className="shelf__title">{title}</h2>
        <div className="shelf__nav">
          <button type="button" onClick={() => scrollBy(-1)} aria-label={`Scroll ${title} left`}>
            <ChevronLeftIcon size={18} />
          </button>
          <button type="button" onClick={() => scrollBy(1)} aria-label={`Scroll ${title} right`}>
            <ChevronRightIcon size={18} />
          </button>
        </div>
      </header>

      <div className="shelf__track" ref={trackRef}>
        {children}
      </div>
    </section>
  )
}

export function AlbumCard({ album, onSelect }) {
  return (
    <button
      type="button"
      className="card card--album"
      onClick={() => onSelect(album.latestPlay)}
      title={`Play ${album.latestPlay.track.name}`}
    >
      <span className="card__art">
        {album.imageUrl ? (
          <img src={album.imageUrl} alt="" loading="lazy" width="208" height="208" />
        ) : (
          <span className="cover--empty" />
        )}
        <span className="card__badge">
          <PlayIcon size={16} />
        </span>
      </span>

      <span className="card__name">{album.name}</span>
      <span className="card__sub">{album.artists}</span>
    </button>
  )
}

// The card body opens the artist; the badge stays a shortcut to play. They are
// siblings rather than nested buttons, which the markup would not allow.
export function ArtistCard({ artist, onOpen, onSelect }) {
  return (
    <div className="card card--artist">
      <button
        type="button"
        className="card__open"
        onClick={() => onOpen(artist)}
        aria-label={`Explore ${artist.name}`}
      >
        <span className="card__art card__art--round">
          {artist.imageUrl ? (
            <img src={artist.imageUrl} alt="" loading="lazy" width="150" height="150" />
          ) : (
            <span className="cover--empty" />
          )}
        </span>

        <span className="card__name">{artist.name}</span>
        <span className="card__sub">{plural(artist.count, "play")}</span>
      </button>

      <button
        type="button"
        className="card__badge"
        onClick={() => onSelect(artist.latestPlay)}
        title={`Play ${artist.latestPlay.track.name}`}
        aria-label={`Play ${artist.latestPlay.track.name} by ${artist.name}`}
      >
        <PlayIcon size={16} />
      </button>
    </div>
  )
}
