import { useCallback, useEffect, useState } from "react"
import { usePlays } from "../hooks/usePlays"
import { fetchStatus } from "../lib/api"
import PlayFeed from "./PlayFeed"
import PlayerDock from "./PlayerDock"
import SetupNotice from "./SetupNotice"

const AUTOPLAY_KEY = "autoplay"

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

  useEffect(() => {
    const controller = new AbortController()
    fetchStatus({ signal: controller.signal })
      .then(setAccount)
      .catch(() => {})
    return () => controller.abort()
  }, [])

  function handleSelect(play) {
    // Clicking the playing track closes the dock.
    setSelected((current) => (current?.id === play.id ? null : play))
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

  // The feed runs newest-first, so the track that follows is the row below.
  // Looking it up by id keeps this correct even when the poll prepends new
  // plays and shifts every index.
  const handleTrackEnded = useCallback(() => {
    if (!autoplay) return

    setSelected((current) => {
      if (!current) return current

      const index = plays.findIndex((play) => play.id === current.id)
      // Nothing left to advance to: stay put, stopped at the end.
      if (index === -1) return current

      return plays[index + 1] ?? current
    })
  }, [autoplay, plays])

  const showSetup = account && !account.connected && plays.length === 0

  return (
    <div className={`shell ${selected ? "shell--docked" : ""}`}>
      <header className="header">
        <p className="header__eyebrow">Spotify</p>
        <h1 className="header__title">Tocando ultimamente</h1>
        <p className="header__subtitle">
          {account?.display_name
            ? `As últimas músicas de ${account.display_name}. Clique em qualquer faixa para ouvir.`
            : "As últimas músicas tocadas. Clique em qualquer faixa para ouvir."}
        </p>
        {account?.plays_count > 0 && (
          <p className="header__stat">
            {account.plays_count.toLocaleString("pt-BR")} reproduções registradas
            {account.last_synced_at && (
              <> · atualizado {new Date(account.last_synced_at).toLocaleString("pt-BR")}</>
            )}
          </p>
        )}
      </header>

      {flash && <p className="flash">{flash}</p>}

      <main className="main">
        {showSetup && <SetupNotice status={account} connectPath={connectPath} />}

        {feedStatus === "loading" && <SkeletonFeed />}

        {feedStatus === "error" && (
          <div className="notice notice--warning">
            <h2>Não deu para carregar as músicas</h2>
            <p>{error?.message}</p>
          </div>
        )}

        {feedStatus === "ready" && plays.length === 0 && !showSetup && (
          <div className="notice">
            <h2>Nada por aqui ainda</h2>
            <p>
              A conta está conectada, mas nenhuma reprodução chegou. Toque algo no Spotify — a
              sincronização roda a cada 5 minutos.
            </p>
          </div>
        )}

        {feedStatus === "ready" && plays.length > 0 && (
          <PlayFeed
            plays={plays}
            selectedPlayId={selected?.id}
            onSelect={handleSelect}
            hasMore={hasMore}
            loadingMore={loadingMore}
            onLoadMore={loadMore}
          />
        )}
      </main>

      {selected && (
        <PlayerDock
          play={selected}
          autoplay={autoplay}
          onToggleAutoplay={toggleAutoplay}
          onEnded={handleTrackEnded}
          onClose={() => setSelected(null)}
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
