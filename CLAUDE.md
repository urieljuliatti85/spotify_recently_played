# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Rails 8.1 + Vite/React 19 + SQLite. Mirrors Spotify listening history (the owner's,
plus friends who accept an invite) into a local database and serves it as a single-page
feed with an in-page player.

`README.md` is the user-facing manual (setup, Spotify app configuration, invites,
privacy, deployment) and is kept current — read it before changing anything user-visible.

## Commands

```bash
bin/setup --skip-server   # bundle + npm + .env + db:prepare. WITHOUT the flag it execs
                          # into bin/dev and never returns — always pass it from an agent.
bin/dev                   # rails :3000 + vite :3036 + solid_queue (Procfile.dev)

bin/rails test                                  # ~97 tests, parallel across cores
bin/rails test test/models/track_test.rb        # one file
bin/rails test test/models/track_test.rb:42     # one test, by line
bin/rubocop                                     # rubocop-rails-omakase; CI fails on any diff after -A
bin/brakeman -q --no-pager
bin/bundler-audit
npm test                                        # Vitest — app/frontend/lib/*.test.js (derive.js, format.js)
```

`bin/ci` (see `config/ci.rb`) runs setup, RuboCop, bundler-audit and Brakeman —
it does **not** run `bin/rails test` or `npm test`. The `.githooks/pre-commit`
hook (already enabled via `core.hooksPath`) runs RuboCop, a frontend build
(`bin/vite build`, to catch a broken JSX/JS file before it ships), the Vitest
suite, and the Rails test suite on every commit.

Rake tasks for operating the feed: `spotify:sync`, `spotify:invite[Label]`,
`spotify:invites`, `spotify:revoke_invite[id]`, `spotify:listeners`,
`spotify:hide[id]`, `spotify:show[id]`, `spotify:unlink[id]`,
`spotify:backfill_artists`, `discogs:check`, `discogs:match`.

### Running the app to verify a change

Use the **`run-spotify-recently-played` skill** (`.claude/skills/`), not `bin/dev`.
`node .claude/skills/run-spotify-recently-played/driver.mjs smoke` builds the bundle,
boots Rails on port 3010, seeds demo listeners, screenshots every offline tab, and tears
down. `bin/dev` starts `bin/jobs`, which spends real Spotify quota on the owner's token,
and headless Chrome will not mount the app off the Vite dev server. The skill's Gotchas
section documents both traps in detail.

## Architecture

### Why there is a database at all

Spotify keeps only the **50 most recent plays** per account. `SyncAllAccountsJob` runs
every minute (`config/recurring.yml`, Solid Queue) and enqueues one
`SyncRecentlyPlayedJob` **per listener** — deliberately not one job for everyone, so a
friend with a dead token retries alone instead of stalling the whole feed.

`Spotify::RecentlyPlayedSync` is the idempotency boundary. Uniqueness is
`(spotify_account_id, played_at)` — an instant identifies a play *within one listener's
history*, since two people can play something at the same second. It loads all stored
`played_at`s for the page in one query and compares them as `getutc.iso8601(3)` strings,
because a Time from the database and one parsed from JSON agree on the instant but not
on `eql?`.

Data model: `Track` is the song, `Play` is each time it was heard, `Artist` exists
separately because the plays payload carries only *simplified* artist objects with no
images — `Spotify::ArtistBackfill` fetches those later. `track_artists.position` holds
credit order; read it through `track_artists`, not `artists`, so `includes` preserves it.

### Two unrelated OAuth flows — do not merge them

1. **Server-side (`Spotify::Authorization`)** links the accounts the site *mirrors*.
   Authorization Code with a client secret; refresh tokens are encrypted at rest
   (`encrypts` on `SpotifyAccount`) and never reach the browser. The owner enters via
   `/spotify/connect` (admin-guarded); a friend enters via `/spotify/join/:token`, whose
   `Invite` stores only a SHA-256 digest. Which row the callback writes to is decided by
   `/v1/me`, not by who started the flow, so a friend's callback cannot land on the
   owner's row. Owner scopes include `playlist-read-private`; `FRIEND_SCOPES` deliberately
   does not.
2. **Browser-side PKCE (`app/frontend/lib/spotifyPkce.js`)** is for a *visitor* who signs
   in only to get a volume slider. Public client, no secret, token in `sessionStorage`,
   redirect at `/listen/callback`. That token must never reach the server and never
   creates a `SpotifyAccount` row — signing in for volume is not consenting to be
   published on the feed.

### Two playback engines

`useSpotifyEmbed` (iframe embed; works signed-out at 30s preview, full track when signed
in to Spotify) and `useWebPlayback` (Web Playback SDK; the only one that can set volume,
requires Premium). `useWebPlayback` reports `unsupported` rather than an error when the
account cannot stream — falling back to the embed is a correct outcome, and free accounts
are the common case. `PlayerBar` switches between them.

### Cost is the recurring design constraint

Public `/api/*` routes spend the *owner's* Spotify quota, so `Api::BaseController`
rate-limits to 60/min: a burst causes a 429 for the whole app, which stalls the sync, and
a stalled sync loses history permanently. Everything that touches Spotify is cached —
artist top tracks 1h, playlists 5min, Discogs shelf lists 2min, `discogs_matches` 30 days.

The same logic drives the Discogs split: `Api::DiscogsController#index` never calls
Spotify and only shows badges some earlier visit already computed; `#show` is allowed to
spend requests, once per release. `Spotify::Client#fetch_each` issues one request per id
on purpose — Spotify's batch `?ids=` forms answer 403 for this app.

### The collection is not read from Discogs here

The Discogs tab reads the sibling **`discogs_shelf`** app over HTTP
(`DISCOGS_SHELF_URL`, default port 3001) via `DiscogsShelf::Client`. That app owns the
Discogs token, sync and rate limiting. `Spotify::ReleaseMatcher` bridges Discogs↔Spotify
by text alone (no shared identifier), so it is guesswork with a hard cap
(`MAX_TRACK_SEARCHES`) and its result is cached in `discogs_matches`.

### Frontend

`App.jsx` is the single stateful root; views are switched by `?view=` and pushed to
history. The API serves only the raw plays feed — **everything else (shelves, artist
pages, listener cards, search, range filter) is derived client-side in `lib/derive.js`**
from the plays already in memory. `usePlays` owns pagination (cursor = `played_at`) and a
60s poll that prepends only genuinely newer rows. The time range is a global lens; the
search box narrows only what is on screen.

`lib/derive.js` and `lib/format.js` are dependency-free ESM, covered by
`*.test.js` files next to them (Vitest, `npm test`), and can also be poked at
directly with `node --input-type=module -e '...'` for a one-off check.

### Auth and CSP

`AdminAuthenticated` guards owner routes with HTTP Basic against `ADMIN_PASSWORD`; with
no password set it waives protection only in development *and* only for `request.local?`.
Routes that skip CSRF (`spotify/syncs`, the OAuth callback) add `CrossSiteGuarded`, which
rejects on `Sec-Fetch-Site` — Basic credentials are replayed by the browser, so Basic
alone is not enough there.

`config/initializers/content_security_policy.rb` is load-bearing and heavily commented:
`open.spotify.com` is only a loader that injects the real API from
`embed-cdn.spotifycdn.com` using the nonce copied from the tag in
`app/views/layouts/application.html.erb`. Adding a Spotify surface usually means touching
both files together.

## Conventions

- Comments in this codebase explain **why**, not what — usually the constraint or the bug
  that forced the shape (rate limits, Spotify quirks, privacy boundaries, race
  conditions). Match that register; do not add restating-the-code comments.
- Ruby style is `rubocop-rails-omakase` verbatim (`.rubocop.yml` adds nothing). CI runs
  `-A` then fails if `git diff` is non-empty, so commit autocorrected output.
- Tests are Minitest with no mocking library. `test/test_helper.rb` provides `stubbing`,
  `stubbing_with` and `with_env`; integration tests get `admin_headers`. The suite sets
  fixed Active Record encryption keys, so neither local runs nor CI need `master.key`.
- Config resolution is `ENV["SPOTIFY_*"]` first, then `credentials.yml.enc` under
  `spotify:` (`Spotify.setting`). `.env` is loaded by dotenv-rails in dev/test only.
- Port 3000 is pinned in `Procfile.dev` because the Spotify redirect URI must match
  exactly; use `127.0.0.1`, never `localhost`.
