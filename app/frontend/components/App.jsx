import { useCallback, useEffect, useMemo, useState } from "react"
import { usePlays } from "../hooks/usePlays"
import { fetchStatus } from "../lib/api"
import { beginLogin, completeLogin, isSignedIn } from "../lib/spotifyPkce"
import {
  albumsFrom,
  artistProfile,
  artistsFrom,
  listenersFrom,
  matching,
  playsOfArtist,
  withinRange,
} from "../lib/derive"
import ArtistView from "./ArtistView"
import AlbumsView from "./AlbumsView"
import DiscogsView from "./DiscogsView"
import Hero from "./Hero"
import PlayFeed from "./PlayFeed"
import ListenersView from "./ListenersView"
import PlayerBar from "./PlayerBar"
import PlaylistView from "./PlaylistView"
import SetupNotice from "./SetupNotice"
import Sidebar from "./Sidebar"
import TopBar, { VIEWS } from "./TopBar"
import TopItemsBox from "./TopItemsBox"
import { AlbumCard, ArtistCard, Shelf } from "./Shelf"

const AUTOPLAY_KEY = "autoplay"
const SIDEBAR_TRACKS = 8
const SHELF_SIZE = 20
const ARTIST_GRID_SIZE = 60
const VIEW_IDS = new Set(VIEWS.map(({ id }) => id))
// Tabs that draw from their own source rather than from the plays feed, so
// they render whether or not anything has been played yet.
const STANDALONE_VIEWS = new Set(["albums", "playlists", "listeners", "discogs"])

// Mirrors the album page's /albums/:id/tracks shape.
const ARTIST_PATH = /^\/artists\/([^/]+)\/tracks\/?$/
// AlbumsView owns the id itself (mirroring DiscogsView's own ?release=
// handling) — this only has to route the tab to mount it.
const ALBUM_PATH = /^\/albums\/[^/]+\/tracks\/?$/

function viewFromUrl() {
  if (ARTIST_PATH.test(window.location.pathname)) return "artists"
  if (ALBUM_PATH.test(window.location.pathname)) return "albums"

  const requested = new URLSearchParams(window.location.search).get("view")
  return VIEW_IDS.has(requested) ? requested : "overview"
}

// The artist's id lives in the path (/artists/:id/tracks) rather than a query
// param, so a link to one specific artist is a URL someone can actually share.
function artistFromUrl() {
  const match = ARTIST_PATH.exec(window.location.pathname)
  return match ? decodeURIComponent(match[1]) : null
}

// Autoplay is on by default: playback only ever starts from a click, so
// continuing down the feed is what someone who pressed play expects.
function readAutoplayPreference() {
  try {
    return window.localStorage.getItem(AUTOPLAY_KEY) !== "off"
  } catch {
    return true
  }
}

export default function App({ connectPath, flash, clientId, listenRedirectUri }) {
  // A visitor signing in to get a volume slider is a different thing from the
  // accounts this site mirrors: the token lives in their browser only, and no
  // listener row is ever created for them.
  const [signedIn, setSignedIn] = useState(isSignedIn)
  // null means "everyone"; an id narrows the feed to one person.
  const [listenerId, setListenerId] = useState(null)
  const { plays, status: feedStatus, error, loadMore, loadAll, loadingMore, hasMore } =
    usePlays({ listener: listenerId })
  const [site, setSite] = useState(null)
  const [selected, setSelected] = useState(null)
  const [autoplay, setAutoplay] = useState(readAutoplayPreference)
  const [range, setRange] = useState("all")
  const [view, setView] = useState(viewFromUrl)
  const [query, setQuery] = useState("")
  const [openArtist, setOpenArtist] = useState(() => {
    const key = artistFromUrl()
    return key ? { key, name: null } : null
  })
  // Which list next/prev walks. null means the visible feed; a credit key
  // means the player stays inside that artist until something else is played.
  const [playScope, setPlayScope] = useState(null)
  const [playQueue, setPlayQueue] = useState(null)

  // Spotify sends the browser back here after the consent screen.
  useEffect(() => {
    if (!clientId) return

    completeLogin({ clientId, redirectUri: listenRedirectUri }).then((justSignedIn) => {
      if (justSignedIn) setSignedIn(true)
    })
  }, [clientId, listenRedirectUri])

  const signIn = useCallback(() => {
    beginLogin({ clientId, redirectUri: listenRedirectUri })
  }, [clientId, listenRedirectUri])

  const handleSignedOut = useCallback(() => setSignedIn(false), [])

  useEffect(() => {
    const controller = new AbortController()
    fetchStatus({ signal: controller.signal })
      .then(setSite)
      .catch(() => {})
    return () => controller.abort()
  }, [])

  useEffect(() => {
    function handlePopState() {
      setView(viewFromUrl())
      const key = artistFromUrl()
      setOpenArtist(key ? { key, name: null } : null)
    }

    window.addEventListener("popstate", handlePopState)
    return () => window.removeEventListener("popstate", handlePopState)
  }, [])

  const listeners = site?.listeners ?? []
  const selectedListener = listeners.find((listener) => listener.id === listenerId) ?? null
  // Only worth tagging every row once there is more than one person to tell
  // apart — and never while the feed is already filtered to one of them.
  const showListener = listeners.length > 1 && listenerId === null

  // The most recent sync across everyone, which is what "Synced 14:02" means
  // on a feed that mixes listeners.
  const lastSyncedAt = useMemo(() => {
    const stamps = listeners.map((listener) => listener.last_synced_at).filter(Boolean)
    return stamps.length > 0 ? stamps.reduce((a, b) => (a > b ? a : b)) : null
  }, [listeners])

  // The range is a global lens; the search only narrows what is on screen. The
  // artist page reads from the ranged set so opening an artist never inherits
  // whatever happened to be typed in the search box.
  const ranged = useMemo(() => withinRange(plays, range), [plays, range])
  const queue = useMemo(() => matching(ranged, query), [ranged, query])

  // The Listeners tab reads the ranged feed rather than the searched one: the
  // search box narrows what is on screen, and a card that hid everyone whose
  // tracks did not match would read as them having stopped listening.
  const listenerCards = useMemo(
    () => (view === "listeners" ? listenersFrom(ranged, listeners) : []),
    [view, ranged, listeners]
  )

  const albums = useMemo(() => albumsFrom(queue, SHELF_SIZE), [queue])
  const recentAlbums = useMemo(() => albumsFrom(ranged, 100), [ranged])
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
    () => playQueue ?? (playScope ? playsOfArtist(ranged, playScope) : queue),
    [playQueue, playScope, ranged, queue]
  )

  const selectedIndex = selected ? activeQueue.findIndex((play) => play.id === selected.id) : -1
  const hasPrev = selectedIndex > 0
  const hasNext = selectedIndex !== -1 && selectedIndex < activeQueue.length - 1

  // Clicking the playing track closes the player.
  const handleSelect = useCallback((play, scope = null, queueOverride = null) => {
    setPlayScope(scope)
    setPlayQueue(queueOverride)
    setSelected((current) => (current?.id === play.id ? null : play))
  }, [])

  const handleSelectInArtist = useCallback(
    (play) => handleSelect(play, openArtist?.key ?? null),
    [handleSelect, openArtist]
  )

  const showArtist = useCallback(({ key, name }) => {
    setOpenArtist({ key, name })
    setView("artists")
    const url = new URL(window.location.href)
    url.pathname = `/artists/${encodeURIComponent(key)}/tracks`
    url.searchParams.delete("view")
    window.history.pushState({ view: "artists", artist: key }, "", url)
    window.scrollTo({ top: 0, behavior: "smooth" })
  }, [])

  // Leaving the artist page without changing tabs — back to the grid, which
  // lives at /?view=artists again rather than under the artist's path.
  const closeArtist = useCallback(() => {
    setOpenArtist(null)
    const url = new URL(window.location.href)
    url.pathname = "/"
    url.searchParams.set("view", "artists")
    window.history.pushState({ view: "artists" }, "", url)
  }, [])

  function changeView(next) {
    setView(next)
    setOpenArtist(null)
    // The tab shows everyone side by side, so a filter left on one person would
    // empty every other card.
    if (next === "listeners") setListenerId(null)

    const url = new URL(window.location.href)
    url.pathname = "/"
    if (next === "overview") {
      url.searchParams.delete("view")
    } else {
      url.searchParams.set("view", next)
    }
    window.history.pushState({ view: next }, "", url)
  }

  function changeRange(next) {
    setRange(next)
    loadAll()
  }

  // Jump from a listener's card into the feed, filtered to them.
  function openListenerFeed(id) {
    changeListener(id)
    changeView("tracks")
  }

  // The sidebar picker, which is reachable from every tab. On the Listeners
  // tab it needs more than a filter change: that tab draws every card from the
  // one feed, so narrowing the feed to one person empties everyone else's card
  // and reads as them having stopped listening. Picking someone there means
  // "show me them", and the feed is where that lives — the same place the
  // card's own "See all plays" button goes.
  function pickListener(next) {
    changeListener(next)
    if (next !== null && view === "listeners") changeView("tracks")
  }

  // Switching listener throws away everything derived from the old feed: the
  // open artist page, the player's queue, and whatever was being played.
  function changeListener(next) {
    setListenerId(next)
    setOpenArtist(null)
    setSelected(null)
    setPlayScope(null)
    setPlayQueue(null)

    if (artistFromUrl()) {
      const url = new URL(window.location.href)
      url.pathname = "/"
      if (view === "overview") {
        url.searchParams.delete("view")
      } else {
        url.searchParams.set("view", view)
      }
      window.history.pushState({ view }, "", url)
    }
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
    // Shuffling walks the list it was handed, so any playlist queue left over
    // from the Playlists tab has to go — otherwise next/prev would be looking
    // for the picked play inside a queue that never contained it.
    setPlayQueue(null)
    setSelected(list[Math.floor(Math.random() * list.length)])
  }

  const showSetup = site && !site.connected && plays.length === 0
  const isReady = feedStatus === "ready"
  const noMatches = isReady && plays.length > 0 && queue.length === 0

  return (
    <div className={`app ${selected ? "app--playing" : ""}`}>
      <Sidebar
        listeners={listeners}
        selectedListenerId={listenerId}
        onListenerChange={pickListener}
        range={range}
        onRangeChange={changeRange}
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
          lastSyncedAt={lastSyncedAt}
        />

        <main className="main">
          {flash && <p className="flash">{flash}</p>}

          {showSetup && <SetupNotice status={site} connectPath={connectPath} />}

          {feedStatus === "loading" && <SkeletonFeed />}

          {feedStatus === "error" && (
            <div className="notice notice--warning">
              <h2>Couldn&apos;t load the tracks</h2>
              <p>{error?.message}</p>
            </div>
          )}

          {isReady && plays.length === 0 && !showSetup && !STANDALONE_VIEWS.has(view) && (
            <div className="notice">
              <h2>Nothing here yet</h2>
              <p>
                {selectedListener
                  ? `${selectedListener.name} is connected, but nothing has come through yet.`
                  : "Connected, but no plays have come through. Play something on Spotify —"}{" "}
                the sync runs every minute.
              </p>
            </div>
          )}

          {isReady && plays.length > 0 && profile && (
            <ArtistView
              profile={profile}
              selectedPlayId={selected?.id}
              onSelect={handleSelectInArtist}
              onBack={closeArtist}
              onShuffle={() => shuffleFrom(profile.plays, profile.key)}
            />
          )}

          {isReady && !profile && view === "playlists" && (
            <PlaylistView onSelect={handleSelect} connectPath={connectPath} />
          )}

          {isReady && !profile && view === "albums" && (
            <AlbumsView albums={recentAlbums} onSelect={handleSelect} />
          )}

          {isReady && !profile && view === "discogs" && (
            <DiscogsView query={query} onSelect={handleSelect} selectedPlayId={selected?.id} />
          )}

          {isReady && !profile && view === "listeners" && (
            <ListenersView
              listeners={listenerCards}
              onSelect={handleSelect}
              onOpenArtist={showArtist}
              onOpenFeed={openListenerFeed}
              selectedPlayId={selected?.id}
              connectPath={connectPath}
            />
          )}

          {isReady && plays.length > 0 && !profile && !STANDALONE_VIEWS.has(view) && (
            <>
              {view === "overview" && (
                <>
                  <Hero
                    listeners={listeners}
                    selectedListener={selectedListener}
                    visibleCount={queue.length}
                    onPlayLatest={() => queue[0] && handleSelect(queue[0])}
                    onShuffle={() => shuffleFrom(queue)}
                  />

                  <TopItemsBox onSelect={handleSelect} onOpenArtist={showArtist} connectPath={connectPath} />

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
                      onOpenArtist={showArtist}
                      showListener={showListener}
                      onPickListener={(listener) => changeListener(listener.id)}
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
          clientId={clientId}
          signedIn={signedIn}
          onSignIn={clientId ? signIn : null}
          onSignedOut={handleSignedOut}
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
