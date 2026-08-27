import { useEffect, useMemo, useState } from "react"
import { fetchDiscogsReleases, fetchDiscogsStatus } from "../lib/api"
import DiscogsRelease from "./DiscogsRelease"
import { ChevronLeftIcon, ChevronRightIcon, DiscIcon } from "./icons"

const LISTS = [
  { id: "collection", label: "Collection" },
  { id: "wantlist", label: "Wantlist" },
]

const SORTS = [
  { id: "added_desc", label: "Recently added" },
  { id: "artist_asc", label: "Artist" },
  { id: "title_asc", label: "Title" },
  { id: "year_desc", label: "Newest" },
  { id: "year_asc", label: "Oldest" },
]

// The shelf filters server-side, so every keystroke would otherwise be a
// request. Long enough to swallow typing, short enough not to feel stuck.
const SEARCH_DELAY = 300

// The open record lives in the URL, next to ?view=, so a link to one is a link
// to it and the browser's back button leaves the record rather than the site.
function releaseFromUrl() {
  const requested = new URLSearchParams(window.location.search).get("release")
  return requested && /^\d+$/.test(requested) ? requested : null
}

function writeReleaseToUrl(discogsId) {
  const url = new URL(window.location.href)
  if (discogsId) {
    url.searchParams.set("release", String(discogsId))
  } else {
    url.searchParams.delete("release")
  }
  window.history.pushState({ view: "discogs", release: discogsId ?? null }, "", url)
}

export default function DiscogsView({ query, onSelect, selectedPlayId }) {
  const [status, setStatus] = useState(null)
  const [list, setList] = useState("collection")
  const [sort, setSort] = useState("added_desc")
  const [genre, setGenre] = useState("")
  const [page, setPage] = useState(1)
  const [payload, setPayload] = useState(null)
  const [state, setState] = useState("loading")
  const [error, setError] = useState(null)
  const [openId, setOpenId] = useState(releaseFromUrl)
  const [search, setSearch] = useState(query)

  useEffect(() => {
    const timer = setTimeout(() => setSearch(query), SEARCH_DELAY)
    return () => clearTimeout(timer)
  }, [query])

  // Any change to what is being asked for starts the list over; page 4 of the
  // old filter is not page 4 of the new one.
  useEffect(() => setPage(1), [list, sort, genre, search])

  useEffect(() => {
    const controller = new AbortController()
    fetchDiscogsStatus({ signal: controller.signal })
      .then(setStatus)
      .catch(() => {})
    return () => controller.abort()
  }, [])

  useEffect(() => {
    function handlePopState() {
      setOpenId(releaseFromUrl())
    }

    window.addEventListener("popstate", handlePopState)
    return () => window.removeEventListener("popstate", handlePopState)
  }, [])

  function openRelease(discogsId) {
    setOpenId(discogsId)
    writeReleaseToUrl(discogsId)
    window.scrollTo({ top: 0, behavior: "smooth" })
  }

  useEffect(() => {
    const controller = new AbortController()
    setState((current) => (current === "ready" ? "refreshing" : "loading"))

    fetchDiscogsReleases({ list, sort, genre, q: search, page, signal: controller.signal })
      .then((result) => {
        setPayload(result)
        setState("ready")
      })
      .catch((cause) => {
        if (controller.signal.aborted) return
        setError(cause)
        setState("error")
      })

    return () => controller.abort()
  }, [list, sort, genre, search, page])

  const items = payload?.items ?? []
  const pagination = payload?.pagination
  const genres = useMemo(() => payload?.facets?.genres ?? [], [payload])

  if (openId) {
    return (
      <DiscogsRelease
        discogsId={openId}
        onBack={() => openRelease(null)}
        onSelect={onSelect}
        selectedPlayId={selectedPlayId}
      />
    )
  }

  if (state === "error") {
    return <ShelfNotice error={error} status={status} />
  }

  return (
    <section className="section discogs">
      <header className="section__head">
        <div>
          <h1 className="section__title">Discogs</h1>
          <p className="section__hint">
            {status?.username ? `${status.username}'s shelf` : "Your shelf"} — open a record to see
            which of its tracks Spotify actually has.
          </p>
        </div>
      </header>

      <div className="discogs-filters">
        <div className="discogs-filters__lists">
          {LISTS.map(({ id, label }) => (
            <button
              key={id}
              type="button"
              className={`discogs-filters__list ${list === id ? "discogs-filters__list--active" : ""}`}
              onClick={() => setList(id)}
              aria-pressed={list === id}
            >
              {label}
              {id === "collection" && status?.collection_count != null && (
                <span className="discogs-filters__count">{status.collection_count}</span>
              )}
              {id === "wantlist" && status?.wantlist_count != null && (
                <span className="discogs-filters__count">{status.wantlist_count}</span>
              )}
            </button>
          ))}
        </div>

        <label className="discogs-filters__select">
          <span>Genre</span>
          <select value={genre} onChange={(event) => setGenre(event.target.value)}>
            <option value="">All</option>
            {genres.map(({ value, count }) => (
              <option key={value} value={value}>
                {value} ({count})
              </option>
            ))}
          </select>
        </label>

        <label className="discogs-filters__select">
          <span>Sort</span>
          <select value={sort} onChange={(event) => setSort(event.target.value)}>
            {SORTS.map(({ id, label }) => (
              <option key={id} value={id}>
                {label}
              </option>
            ))}
          </select>
        </label>
      </div>

      {state === "loading" && <p className="section__hint">Loading the shelf…</p>}

      {state !== "loading" && items.length === 0 && (
        <p className="section__hint">
          Nothing in this {list}
          {search && <> for “{search}”</>}.
        </p>
      )}

      <div className="discogs-grid">
        {items.map((item) => (
          <ReleaseCard key={item.discogs_id} item={item} onOpen={() => openRelease(item.discogs_id)} />
        ))}
      </div>

      {pagination && pagination.total_pages > 1 && (
        <div className="discogs-pager">
          <button
            type="button"
            className="icon-btn"
            onClick={() => setPage((current) => Math.max(1, current - 1))}
            disabled={pagination.page <= 1}
            aria-label="Previous page"
          >
            <ChevronLeftIcon size={16} />
          </button>
          <span>
            {pagination.page} / {pagination.total_pages} · {pagination.total} records
          </span>
          <button
            type="button"
            className="icon-btn"
            onClick={() => setPage((current) => Math.min(pagination.total_pages, current + 1))}
            disabled={pagination.page >= pagination.total_pages}
            aria-label="Next page"
          >
            <ChevronRightIcon size={16} />
          </button>
        </div>
      )}
    </section>
  )
}

function ReleaseCard({ item, onOpen }) {
  return (
    <button type="button" className="discogs-card" onClick={onOpen}>
      <span className="discogs-card__art">
        {item.cover_url || item.thumb_url ? (
          <img src={item.cover_url || item.thumb_url} alt="" loading="lazy" width="200" height="200" />
        ) : (
          <span className="cover--empty" />
        )}
        <MatchBadge spotify={item.spotify} />
      </span>

      <span className="discogs-card__title">{item.title}</span>
      <span className="discogs-card__artist">{item.artist}</span>
      <span className="discogs-card__sub">
        {[item.year, item.format_summary].filter(Boolean).join(" · ")}
      </span>
    </button>
  )
}

// Only records somebody has already opened carry a badge: working out whether
// a release is on Spotify costs requests, and the grid is not where they get
// spent. No badge means unknown, not missing.
function MatchBadge({ spotify }) {
  if (!spotify) return null

  if (spotify.playable_count === 0) {
    return <span className="discogs-card__badge discogs-card__badge--absent">Not on Spotify</span>
  }

  return (
    <span className="discogs-card__badge">
      {spotify.playable_count}/{spotify.track_count} on Spotify
    </span>
  )
}

function ShelfNotice({ error, status }) {
  const configured = status?.configured ?? error?.status !== 503

  return (
    <section className="section">
      <div className="notice notice--warning">
        <h2>
          <DiscIcon size={18} /> The Discogs shelf isn&apos;t answering
        </h2>
        <p>{error?.message}</p>

        {!configured ? (
          <p>
            Point this app at your <code>discogs_shelf</code> install by setting{" "}
            <code>DISCOGS_SHELF_URL</code> in <code>.env</code>, then restart the server.
          </p>
        ) : (
          <p>
            <code>{status?.url}</code> is configured but nothing answered there. Start the shelf with{" "}
            <code>bin/rails server -p 3001</code> in the <code>discogs_shelf</code> repo.
          </p>
        )}
      </div>
    </section>
  )
}
