import CatalogSearch from "./CatalogSearch"
import PlayFeed from "./PlayFeed"

// The screen the top bar's search box switches to the moment there's a
// query, whatever tab was open — it replaces that tab's content rather than
// filtering it in place, because a query reaches past what's on screen (see
// CatalogSearch) and that doesn't fit squeezed under, say, the Listeners
// grid. Clearing the query needs no "back" of its own: `view` in App.jsx was
// never touched, so whatever tab was active is just what renders again.
export default function SearchView({
  query,
  matches,
  onSelect,
  selectedPlayId,
  onOpenArtist,
  showListener,
  onPickListener,
  onOpenAlbum,
}) {
  return (
    <>
      <header className="section__head">
        <div>
          <h1 className="section__title">Search</h1>
          <p className="section__hint">
            {matches.length > 0
              ? `${matches.length} on the feed already for “${query}” — plus whatever else Spotify has.`
              : `Nothing on the feed yet for “${query}” — here’s what Spotify has.`}
          </p>
        </div>
      </header>

      {matches.length > 0 && (
        <section className="section">
          <h2 className="section__title">Already played</h2>
          <PlayFeed
            plays={matches}
            selectedPlayId={selectedPlayId}
            onSelect={onSelect}
            onOpenArtist={onOpenArtist}
            showListener={showListener}
            onPickListener={onPickListener}
            hasMore={false}
            loadingMore={false}
            onLoadMore={() => {}}
          />
        </section>
      )}

      <CatalogSearch query={query} onSelectTrack={onSelect} onOpenAlbum={onOpenAlbum} />
    </>
  )
}
