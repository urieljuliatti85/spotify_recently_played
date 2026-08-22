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
