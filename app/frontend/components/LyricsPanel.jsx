import { useEffect, useRef } from "react"
import { activeLyricIndex } from "../lib/format"
import { CloseIcon } from "./icons"

// The panel that opens above the PlayerBar when "Lyrics" is toggled on.
// Synced lyrics (lrclib's LRC format) get a highlighted, auto-scrolling
// current line; plain lyrics fall back to static text; anything else is a
// short explanatory note rather than an empty box.
export default function LyricsPanel({ state, plainLyrics, syncedLines, instrumental, position, onClose }) {
  const activeRef = useRef(null)
  const activeIndex = syncedLines.length > 0 ? activeLyricIndex(syncedLines, position) : -1

  useEffect(() => {
    activeRef.current?.scrollIntoView({ block: "center", behavior: "smooth" })
  }, [activeIndex])

  return (
    <div className="lyrics-panel" role="region" aria-label="Lyrics">
      <div className="lyrics-panel__head">
        <h2 className="lyrics-panel__title">Lyrics</h2>
        <button type="button" className="icon-btn" onClick={onClose} aria-label="Close lyrics">
          <CloseIcon size={14} />
        </button>
      </div>

      <div className="lyrics-panel__body">
        {state === "loading" && <p className="lyrics-panel__hint">Loading lyrics…</p>}
        {state === "error" && <p className="lyrics-panel__hint">Couldn&apos;t load lyrics right now.</p>}
        {state === "missing" && <p className="lyrics-panel__hint">No lyrics found for this track.</p>}

        {state === "ready" && instrumental && (
          <p className="lyrics-panel__hint">Instrumental — no lyrics for this track.</p>
        )}

        {state === "ready" && !instrumental && syncedLines.length > 0 && (
          <ol className="lyrics-panel__lines">
            {syncedLines.map((line, index) => (
              <li
                key={`${line.time}-${index}`}
                ref={index === activeIndex ? activeRef : null}
                className={`lyrics-panel__line ${index === activeIndex ? "lyrics-panel__line--active" : ""}`}
              >
                {line.text}
              </li>
            ))}
          </ol>
        )}

        {state === "ready" && !instrumental && syncedLines.length === 0 && plainLyrics && (
          <p className="lyrics-panel__plain">{plainLyrics}</p>
        )}
      </div>
    </div>
  )
}
