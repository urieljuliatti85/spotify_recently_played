const HEADERS = { Accept: "application/json" }

async function request(path, { signal, method = "GET", body } = {}) {
  const headers = body ? { ...HEADERS, "Content-Type": "application/json" } : HEADERS
  // Same-origin credentials on purpose: the owner-only routes are guarded by
  // HTTP Basic, and the browser only replays those when it is allowed to.
  const response = await fetch(path, {
    headers,
    method,
    signal,
    credentials: "same-origin",
    body: body ? JSON.stringify(body) : undefined,
  })

  if (!response.ok) {
    // Every endpoint here answers JSON on failure too, and its `error` says
    // something a visitor can act on ("Discogs Shelf did not answer") where a
    // status code says nothing.
    const message = await response
      .clone()
      .json()
      .then((payload) => payload?.error)
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

export function fetchTopItems({ signal } = {}) {
  return request("/api/top_items", { signal })
}

export function fetchFollowedArtists({ signal } = {}) {
  return request("/api/followed_artists", { signal })
}

export function fetchArtistTracks(artistId, { signal } = {}) {
  return request(`/api/artists/${encodeURIComponent(artistId)}/tracks`, { signal })
}

export function fetchAlbumTracks(albumId, { signal } = {}) {
  return request(`/api/albums/${encodeURIComponent(albumId)}/tracks`, { signal })
}

export function fetchAlbumDiscogs(albumId, { signal } = {}) {
  return request(`/api/albums/${encodeURIComponent(albumId)}/discogs`, { signal })
}

export function fetchAlbumReleases({ title, artist, signal } = {}) {
  const params = new URLSearchParams({ title, artist })
  return request(`/api/albums/releases?${params}`, { signal })
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

// Owner-only. Both of these spend the owner's Spotify quota — the first reads
// one catalogue search per artist, the second writes to their account — so
// they live outside /api and answer 401 to anyone else.
export function fetchUnheardTracks({ signal } = {}) {
  return request("/spotify/playlists/unheard", { signal })
}

export function searchPlaylistTracks(query, { signal } = {}) {
  const params = new URLSearchParams({ q: query })
  return request(`/spotify/playlists/search?${params}`, { signal })
}

export function createUnheardPlaylist({ name, trackIds, signal } = {}) {
  return request("/spotify/playlists", {
    method: "POST",
    body: { name, track_ids: trackIds },
    signal,
  })
}

// Pulls recent plays for every linked listener right now instead of waiting
// for the schedule (SyncAllAccountsJob still runs every minute regardless).
export function syncNow({ signal } = {}) {
  return request("/spotify/sync", { method: "POST", signal })
}

export function createInvite(label, { signal } = {}) {
  return request("/spotify/invites", {
    method: "POST",
    body: { label },
    signal,
  })
}
