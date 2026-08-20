import { groupByDay } from "../lib/format"
import PlayRow from "./PlayRow"

export default function PlayFeed({ plays, selectedPlayId, onSelect, hasMore, loadingMore, onLoadMore }) {
  const groups = groupByDay(plays)

  return (
    <div className="feed">
      {groups.map((group) => (
        <section className="feed__day" key={group.key}>
          <h2 className="feed__day-label">{group.label}</h2>
          <ul className="feed__list">
            {group.plays.map((play) => (
              <PlayRow
                key={play.id}
                play={play}
                isSelected={play.id === selectedPlayId}
                onSelect={onSelect}
              />
            ))}
          </ul>
        </section>
      ))}

      {hasMore && (
        <button type="button" className="feed__more" onClick={onLoadMore} disabled={loadingMore}>
          {loadingMore ? "Carregando…" : "Carregar mais"}
        </button>
      )}
    </div>
  )
}
