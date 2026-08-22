const HEADERS = { Accept: "application/json" }

async function request(path, { signal } = {}) {
  const response = await fetch(path, { headers: HEADERS, signal })

  if (!response.ok) {
    throw new Error(`Request to ${path} failed with ${response.status}`)
  }

  return response.json()
}

export function fetchPlays({ before, limit = 30, listener, signal } = {}) {
  const params = new URLSearchParams({ limit: String(limit) })
  if (before) params.set("before", before)
  if (listener) params.set("listener", String(listener))

  return request(`/api/plays?${params}`, { signal })
}

export function fetchStatus({ signal } = {}) {
  return request("/api/status", { signal })
}

export function fetchArtistTracks(artistId, { signal } = {}) {
  return request(`/api/artists/${encodeURIComponent(artistId)}/tracks`, { signal })
}

export function fetchPlaylists({ signal } = {}) {
  return request("/api/playlists", { signal })
}

export function fetchPlaylistTracks(playlistId, { signal } = {}) {
  return request(`/api/playlists/${encodeURIComponent(playlistId)}/tracks`, { signal })
}
