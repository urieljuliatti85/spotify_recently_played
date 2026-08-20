import { useSpotifyEmbed } from "../hooks/useSpotifyEmbed"

export default function PlayerDock({ play, autoplay, onToggleAutoplay, onEnded, onClose }) {
  const { containerRef, state } = useSpotifyEmbed(play?.track?.spotify_id, { onEnded })

  return (
    <div className="dock" role="region" aria-label="Player">
      <div className="dock__inner">
        <div className="dock__now">
          <span className="dock__label">Tocando agora</span>
          <span className="dock__track">{play.track.name}</span>
          <span className="dock__artists">{play.track.artists}</span>

          <label className="dock__autoplay">
            <input type="checkbox" checked={autoplay} onChange={onToggleAutoplay} />
            <span>Tocar a próxima automaticamente</span>
          </label>
        </div>

        <div className="dock__player">
          {/* Spotify's API replaces this node with the embed iframe. */}
          <div ref={containerRef} />

          {state === "loading" && <p className="dock__hint">Carregando o player…</p>}

          {state === "unavailable" && (
            <iframe
              title={`Player de ${play.track.name}`}
              src={`https://open.spotify.com/embed/track/${play.track.spotify_id}?theme=0`}
              width="100%"
              height="152"
              frameBorder="0"
              loading="lazy"
              allow="autoplay; clipboard-write; encrypted-media; fullscreen; picture-in-picture"
            />
          )}
        </div>

        <button type="button" className="dock__close" onClick={onClose} aria-label="Fechar player">
          ✕
        </button>
      </div>
    </div>
  )
}
