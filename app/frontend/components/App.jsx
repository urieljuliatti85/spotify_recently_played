import { useCallback, useEffect, useMemo, useState } from "react"
import { usePlays } from "../hooks/usePlays"
import { fetchStatus } from "../lib/api"
import { albumsFrom, artistProfile, artistsFrom, matching, playsOfArtist, withinRange } from "../lib/derive"
import ArtistView from "./ArtistView"
import Hero from "./Hero"
import PlayFeed from "./PlayFeed"
import PlayerBar from "./PlayerBar"
import SetupNotice from "./SetupNotice"
import Sidebar from "./Sidebar"
import TopBar from "./TopBar"
import { AlbumCard, ArtistCard, Shelf } from "./Shelf"

const AUTOPLAY_KEY = "autoplay"
const SIDEBAR_TRACKS = 8
const SHELF_SIZE = 20
const ARTIST_GRID_SIZE = 60

// Autoplay is on by default: playback only ever starts from a click, so
// continuing down the feed is what someone who pressed play expects.
function readAutoplayPreference() {
  try {
    return window.localStorage.getItem(AUTOPLAY_KEY) !== "off"
  } catch {
    return true
  }
}

export default function App({ connectPath, flash }) {
  const { plays, status: feedStatus, error, loadMore, loadingMore, hasMore } = usePlays()
  const [account, setAccount] = useState(null)
  const [selected, setSelected] = useState(null)
  const [autoplay, setAutoplay] = useState(readAutoplayPreference)
  const [range, setRange] = useState("all")
  const [view, setView] = useState("overview")
  const [query, setQuery] = useState("")
  const [openArtist, setOpenArtist] = useState(null)
  // Which list next/prev walks. null means the visible feed; a credit key
  // means the player stays inside that artist until something else is played.
  const [playScope, setPlayScope] = useState(null)

  useEffect(() => {
    const controller = new AbortController()
    fetchStatus({ signal: controller.signal })
      .then(setAccount)
      .catch(() => {})
    return () => controller.abort()
  }, [])

  // The range is a global lens; the search only narrows what is on screen. The
  // artist page reads from the ranged set so opening an artist never inherits
  // whatever happened to be typed in the search box.
  const ranged = useMemo(() => withinRange(plays, range), [plays, range])
  const queue = useMemo(() => matching(ranged, query), [ranged, query])

  const albums = useMemo(() => albumsFrom(queue, SHELF_SIZE), [queue])
  const artists = useMemo(
    () => artistsFrom(queue, view === "artists" ? ARTIST_GRID_SIZE : SHELF_SIZE),
    [queue, view]
  )

  // Opening an artist carries their name along, so the page still has a label
  // when the range hides every play they appear on.
  const profile = useMemo(
    () => (openArtist ? artistProfile(ranged, openArtist.key, { name: openArtist.name }) : null),
    [openArtist, ranged]
  )

  // Derived rather than stored, so a poll that adds plays extends the queue the
  // player is already walking.
  const activeQueue = useMemo(
    () => (playScope ? playsOfArtist(ranged, playScope) : queue),
    [playScope, ranged, queue]
  )

  const selectedIndex = selected ? activeQueue.findIndex((play) => play.id === selected.id) : -1
  const hasPrev = selectedIndex > 0
  const hasNext = selectedIndex !== -1 && selectedIndex < activeQueue.length - 1

  // Clicking the playing track closes the player.
  const handleSelect = useCallback((play, scope = null) => {
    setPlayScope(scope)
    setSelected((current) => (current?.id === play.id ? null : play))
  }, [])

  const handleSelectInArtist = useCallback(
    (play) => handleSelect(play, openArtist?.key ?? null),
    [handleSelect, openArtist]
  )

  const showArtist = useCallback(({ key, name }) => {
    setOpenArtist({ key, name })
    setView("artists")
    window.scrollTo({ top: 0, behavior: "smooth" })
  }, [])

  function changeView(next) {
    setView(next)
    setOpenArtist(null)
  }

  function toggleAutoplay() {
    setAutoplay((current) => {
      const next = !current
      try {
        window.localStorage.setItem(AUTOPLAY_KEY, next ? "on" : "off")
      } catch {
        // Private browsing: the choice just won't survive a reload.
      }
      return next
    })
  }

  // The queue runs newest-first, so the track that follows is the row below.
  // Looking it up by id keeps this correct even when the poll prepends new
  // plays and shifts every index.
  const step = useCallback(
    (offset) => {
      setSelected((current) => {
        if (!current) return current

        const index = activeQueue.findIndex((play) => play.id === current.id)
        if (index === -1) return current

        return activeQueue[index + offset] ?? current
      })
    },
    [activeQueue]
  )

  const handleTrackEnded = useCallback(() => {
    if (!autoplay) return
    step(1)
  }, [autoplay, step])

  function shuffleFrom(list, scope = null) {
    if (list.length === 0) return
    setPlayScope(scope)
    setSelected(list[Math.floor(Math.random() * list.length)])
  }

  const showSetup = account && !account.connected && plays.length === 0
  const isReady = feedStatus === "ready"
  const noMatches = isReady && plays.length > 0 && queue.length === 0

  return (
    <div className={`app ${selected ? "app--playing" : ""}`}>
      <Sidebar
        account={account}
        range={range}
        onRangeChange={setRange}
        recent={queue.slice(0, SIDEBAR_TRACKS)}
        selectedPlayId={selected?.id}
        onSelect={handleSelect}
      />

      <div className="content">
        <TopBar
          view={view}
          onViewChange={changeView}
          query={query}
          onQueryChange={setQuery}
          account={account}
        />

        <main className="main">
          {flash && <p className="flash">{flash}</p>}

          {showSetup && <SetupNotice status={account} connectPath={connectPath} />}

          {feedStatus === "loading" && <SkeletonFeed />}

          {feedStatus === "error" && (
            <div className="notice notice--warning">
              <h2>Couldn&apos;t load the tracks</h2>
              <p>{error?.message}</p>
            </div>
          )}

          {isReady && plays.length === 0 && !showSetup && (
            <div className="notice">
              <h2>Nothing here yet</h2>
              <p>
                The account is connected, but no plays have come through. Play something on Spotify —
                the sync runs every 5 minutes.
              </p>
            </div>
          )}

          {isReady && plays.length > 0 && profile && (
            <ArtistView
              profile={profile}
              selectedPlayId={selected?.id}
              onSelect={handleSelectInArtist}
              onBack={() => setOpenArtist(null)}
              onShuffle={() => shuffleFrom(profile.plays, profile.key)}
            />
          )}

          {isReady && plays.length > 0 && !profile && (
            <>
              {view === "overview" && (
                <>
                  <Hero
                    account={account}
                    visibleCount={queue.length}
                    onPlayLatest={() => queue[0] && handleSelect(queue[0])}
                    onShuffle={() => shuffleFrom(queue)}
                  />

                  {albums.length > 0 && (
                    <Shelf title="Recent Albums">
                      {albums.map((album) => (
                        <AlbumCard key={album.key} album={album} onSelect={handleSelect} />
                      ))}
                    </Shelf>
                  )}

                  {artists.length > 0 && (
                    <Shelf title="Top Artists">
                      {artists.map((artist) => (
                        <ArtistCard
                          key={artist.key}
                          artist={artist}
                          onOpen={showArtist}
                          onSelect={handleSelect}
                        />
                      ))}
                    </Shelf>
                  )}
                </>
              )}

              {!noMatches &&
                (view === "artists" ? (
                  <section className="section">
                    <h2 className="section__title">Artists</h2>
                    <p className="section__hint">Pick anyone to see everything they turn up on.</p>
                    <div className="grid">
                      {artists.map((artist) => (
                        <ArtistCard
                          key={artist.key}
                          artist={artist}
                          onOpen={showArtist}
                          onSelect={handleSelect}
                        />
                      ))}
                    </div>
                  </section>
                ) : (
                  <section className="section">
                    <h2 className="section__title">Recently Played</h2>
                    <PlayFeed
                      plays={queue}
                      selectedPlayId={selected?.id}
                      onSelect={handleSelect}
                      hasMore={hasMore}
                      loadingMore={loadingMore}
                      onLoadMore={loadMore}
                    />
                  </section>
                ))}

              {noMatches && (
                <div className="notice">
                  <h2>No tracks match</h2>
                  <p>
                    Nothing in this range{query && <> for “{query}”</>}. Try a wider range or a
                    different search.
                  </p>
                </div>
              )}
            </>
          )}
        </main>
      </div>

      {selected && (
        <PlayerBar
          play={selected}
          autoplay={autoplay}
          onToggleAutoplay={toggleAutoplay}
          onEnded={handleTrackEnded}
          onClose={() => setSelected(null)}
          onPrev={() => step(-1)}
          onNext={() => step(1)}
          onOpenArtist={showArtist}
          hasPrev={hasPrev}
          hasNext={hasNext}
        />
      )}
    </div>
  )
}

function SkeletonFeed() {
  return (
    <ul className="skeleton" aria-hidden="true">
      {Array.from({ length: 6 }, (_, index) => (
        <li key={index} className="skeleton__row" />
      ))}
    </ul>
  )
}
