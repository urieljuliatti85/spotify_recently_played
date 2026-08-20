const HEADERS = { Accept: "application/json" }

async function request(path, { signal } = {}) {
  const response = await fetch(path, { headers: HEADERS, signal })

  if (!response.ok) {
    throw new Error(`Request to ${path} failed with ${response.status}`)
  }

  return response.json()
}

export function fetchPlays({ before, limit = 30, signal } = {}) {
  const params = new URLSearchParams({ limit: String(limit) })
  if (before) params.set("before", before)

  return request(`/api/plays?${params}`, { signal })
}

export function fetchStatus({ signal } = {}) {
  return request("/api/status", { signal })
}
