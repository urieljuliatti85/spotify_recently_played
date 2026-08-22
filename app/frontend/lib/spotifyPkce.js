/**
 * Authorization Code + PKCE, run entirely in the visitor's browser.
 *
 * This is a second, unrelated OAuth flow: `Spotify::Authorization` links the
 * accounts the site *mirrors*, and its tokens are encrypted in the database.
 * These tokens belong to whoever is *listening* right now, and they must never
 * reach our server or land in `spotify_accounts` — someone who signs in for a
 * volume slider is not asking to be published on the feed. PKCE is what makes
 * that possible: no client secret, so no backend has to be involved.
 *
 * sessionStorage rather than localStorage: the token dies with the tab, which
 * is the right lifetime for a stranger's credential on a public page.
 */

const AUTH_HOST = "https://accounts.spotify.com"

// What the Web Playback SDK requires and nothing more. `streaming` is the
// playback grant; Spotify rejects it unless the two profile scopes come along.
const SCOPES = ["streaming", "user-read-email", "user-read-private"]

// Refresh a little early so a token never expires mid-track.
const EXPIRY_MARGIN_MS = 60_000

const KEY = {
  token: "spotify:listen:token",
  verifier: "spotify:listen:verifier",
  state: "spotify:listen:state",
}

// Private browsing throws on access rather than returning null, so every touch
// is guarded. A visitor who blocks storage simply cannot stay signed in.
function read(key) {
  try {
    return window.sessionStorage.getItem(key)
  } catch {
    return null
  }
}

function write(key, value) {
  try {
    window.sessionStorage.setItem(key, value)
  } catch {
    // Nothing to do: the flow below fails closed and the embed takes over.
  }
}

function drop(key) {
  try {
    window.sessionStorage.removeItem(key)
  } catch {
    // Same story.
  }
}

function base64url(bytes) {
  return btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "")
}

function randomString(byteLength = 48) {
  return base64url(window.crypto.getRandomValues(new Uint8Array(byteLength)))
}

async function challengeFrom(verifier) {
  const digest = await window.crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier))
  return base64url(digest)
}

function storedToken() {
  const raw = read(KEY.token)
  if (!raw) return null

  try {
    return JSON.parse(raw)
  } catch {
    drop(KEY.token)
    return null
  }
}

function storeToken(payload) {
  write(
    KEY.token,
    JSON.stringify({
      access_token: payload.access_token,
      // Spotify only re-issues a refresh token sometimes; keep the old one.
      refresh_token: payload.refresh_token || storedToken()?.refresh_token || null,
      expires_at: Date.now() + Number(payload.expires_in || 0) * 1000,
    })
  )
}

export function isSignedIn() {
  return Boolean(storedToken())
}

export function signOut() {
  drop(KEY.token)
  drop(KEY.verifier)
  drop(KEY.state)
}

/** Sends the browser to Spotify's consent screen. Never returns. */
export async function beginLogin({ clientId, redirectUri }) {
  const verifier = randomString()
  const state = randomString(16)

  write(KEY.verifier, verifier)
  write(KEY.state, state)

  const query = new URLSearchParams({
    client_id: clientId,
    response_type: "code",
    redirect_uri: redirectUri,
    scope: SCOPES.join(" "),
    state,
    code_challenge_method: "S256",
    code_challenge: await challengeFrom(verifier),
  })

  window.location.assign(`${AUTH_HOST}/authorize?${query}`)
}

/**
 * Finishes the flow when Spotify sends the browser back. Returns `true` only
 * when this page load *was* the callback and the exchange succeeded, so the
 * caller can tell "just signed in" from "was already signed in".
 *
 * The query string is scrubbed either way: an authorization code is single-use
 * and has no business surviving in the address bar or in a shared link.
 */
export async function completeLogin({ clientId, redirectUri }) {
  const params = new URLSearchParams(window.location.search)
  const code = params.get("code")
  const returnedState = params.get("state")
  const denied = params.get("error")

  if (!code && !denied) return false

  const expectedState = read(KEY.state)
  const verifier = read(KEY.verifier)
  drop(KEY.state)
  drop(KEY.verifier)
  scrubQuery()

  if (denied) return false
  // The state check is what stops someone else's authorization code from being
  // planted on this browser through a crafted link.
  if (!expectedState || returnedState !== expectedState || !verifier) return false

  const response = await fetch(`${AUTH_HOST}/api/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      code,
      redirect_uri: redirectUri,
      client_id: clientId,
      code_verifier: verifier,
    }),
  })

  if (!response.ok) return false

  storeToken(await response.json())
  return true
}

/**
 * A usable access token, refreshed when it is close to expiring. Returns null
 * when nobody is signed in or the refresh fails, which is the signal to drop
 * back to the embed rather than to show an error: not being signed in is the
 * ordinary case on a public page.
 */
export async function currentToken({ clientId }) {
  const token = storedToken()
  if (!token) return null

  if (Date.now() < token.expires_at - EXPIRY_MARGIN_MS) return token.access_token
  if (!token.refresh_token) {
    signOut()
    return null
  }

  const response = await fetch(`${AUTH_HOST}/api/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: token.refresh_token,
      client_id: clientId,
    }),
  })

  if (!response.ok) {
    signOut()
    return null
  }

  const payload = await response.json()
  storeToken(payload)
  return payload.access_token
}

// Drops the OAuth parameters while leaving the app's own (`?view=`) alone.
function scrubQuery() {
  const url = new URL(window.location.href)
  for (const key of ["code", "state", "error"]) url.searchParams.delete(key)
  window.history.replaceState(window.history.state, "", url)
}
