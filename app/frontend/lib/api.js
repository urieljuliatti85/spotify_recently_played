const HEADERS = { Accept: "application/json" }

async function request(path, { signal } = {}) {
  const response = await fetch(path, { headers: HEADERS, signal })

  if (!response.ok) {
    // Every endpoint here answers JSON on failure too, and its `error` says
    // something a visitor can act on ("Discogs Shelf did not answer") where a
    // status code says nothing.
    const message = await response
      .clone()
      .json()
      .then((body) => body?.error)
      .catch(() => null)

    const failure = new Error(message || `Request to ${path} failed with ${response.status}`)
    failure.status = response.status
    throw failure
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

export function fetchDiscogsStatus({ signal } = {}) {
  return request("/api/discogs/status", { signal })
}

export function fetchDiscogsReleases({ list = "collection", signal, ...filters } = {}) {
  const params = new URLSearchParams({ list })
  for (const [key, value] of Object.entries(filters)) {
    if (value !== null && value !== undefined && value !== "") params.set(key, String(value))
  }

  return request(`/api/discogs/releases?${params}`, { signal })
}

export function fetchDiscogsRelease(discogsId, { signal } = {}) {
  return request(`/api/discogs/releases/${encodeURIComponent(discogsId)}`, { signal })
}
