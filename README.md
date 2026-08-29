# Recently played

A site that shows the latest tracks played on your Spotify account—and on your
friends' accounts, once they've joined—and lets visitors listen to each track
without leaving the page.

- **Backend:** Ruby on Rails 8.1 (API + pages)
- **Frontend:** React 19 via Vite (`vite_rails`)
- **Database:** SQLite (development/test), PostgreSQL (production)
- **Player:** official Spotify embed

## How it works

Spotify stores only the **50 most recent plays** for an account. The app therefore
does not query the API on every visit: a job runs every minute, fetches new
plays, and stores them in SQLite. The site's history grows over time, even after
Spotify has discarded older tracks.

```
                        ┌─▶ SyncRecentlyPlayedJob (you)     ─┐
Spotify API ──(1 min)──▶│                                    ├─▶ SQLite
      SyncAllAccountsJob └─▶ SyncRecentlyPlayedJob (friend)  ─┘      │
                                                                     │
                                   React  ◀──  /api/plays  ◀─────────┘
```

One sync job per listener, rather than one job for everybody: a friend whose
token has gone bad retries on its own without stalling anyone else's history.

Each play is identified by the listener plus the time it was played, which
together have a unique index—syncing the same window twice does not create
duplicates, and two people playing something at the same second are still two
plays. Syncing loads all `played_at` values for the page in a single query
instead of asking the database about each track: the usual poll brings back 50
plays that are already stored and imports none.

## Friends

The feed can mirror more than one account. Each friend links their own—there is
no way to add someone else's listening without them authorizing it, and no
Spotify API for reading a friend's activity.

Issue a single-use invite pinned to their Spotify account — find their id at
`open.spotify.com/user/<id>` on their profile page:

```bash
bin/rails "spotify:invite[<their-spotify-user-id>]"
# → http://your-site/spotify/join/<token>   (single use, expires in 7 days)
```

Send them the link. They authorize with Spotify and their plays start appearing
on the feed. The invite only works for the account it names — the callback
checks the account Spotify hands back against the id the invite was issued
for, so it cannot be claimed by whichever Spotify account happens to be
signed in on a shared or borrowed browser. The link never exposes
`ADMIN_PASSWORD`, and only its digest is stored, so a database copy cannot be
replayed into an account link.

A friend is asked for `user-read-recently-played` and nothing else—the
playlists tab only ever shows the owner's, so asking for a friend's private
playlists would be taking more than the site can use.

Managing who is on the feed:

```bash
bin/rails spotify:listeners          # who is linked, visible, and how many plays
bin/rails spotify:invites            # every invite and what became of it
bin/rails "spotify:revoke_invite[2]" # kill an unclaimed link
bin/rails "spotify:hide[3]"          # off the public feed, plays kept and still syncing
bin/rails "spotify:show[3]"          # back on
bin/rails "spotify:unlink[3]"        # unlink and delete their history
```

For a friend to actually complete the flow, `SPOTIFY_REDIRECT_URI` has to point
at a URL they can reach (not `127.0.0.1`) and that exact URI has to be
registered in your Spotify app's dashboard.

## Configuration

### 1. Create a Spotify app

1. Go to <https://developer.spotify.com/dashboard> and click **Create app**.
2. Under **Redirect URIs**, add **both** of these exactly (missing either one
   fails with `redirect_uri: Not matching configuration` the first time that
   flow is used, not at setup, since the two are unrelated OAuth flows that
   only share the same Spotify app registration):
   - `http://127.0.0.1:3000/spotify/callback` — linking the accounts the site
     mirrors (the owner, and friends via invite).
   - `http://127.0.0.1:3000/listen/callback` — a visitor signing in for the
     volume slider; nothing about this one reaches the server (see "Two
     unrelated OAuth flows" in `CLAUDE.md` for why they're kept separate).

   Spotify requires the loopback IP (`127.0.0.1`) and does not accept `localhost`.
3. Under **APIs used**, select **Web API**.
4. Copy the **Client ID** and **Client Secret**.

The app requests four scopes: `user-read-recently-played` (history),
`playlist-read-private` (the playlists tab), `playlist-modify-public`
(building a playlist from that tab) and `user-top-read` (the Overview's
"SpotPlayer's Top Items" box). Friends grant only the first. If you connected
the account before one of these was asked for, redo `/spotify/connect`—without
the scope, the feature returns 403 and explains this on screen.

### 2. Configure the project

```bash
cp .env.example .env
```

Fill in `.env`:

```
SPOTIFY_CLIENT_ID=your_client_id
SPOTIFY_CLIENT_SECRET=your_client_secret
SPOTIFY_REDIRECT_URI=http://127.0.0.1:3000/spotify/callback
ADMIN_PASSWORD=any_password
DISCOGS_SHELF_URL=http://127.0.0.1:3001   # optional, for the Discogs tab
SPOTIFY_MARKET=BR                         # optional, see Discogs below
YOUTUBE_API_KEY=your_youtube_api_key      # optional, for the feed's video clip links
```

`.env` is already in `.gitignore`. Credentials can also be stored in
`config/credentials.yml.enc` under the `spotify:` key—`.env` takes precedence.

### 3. Start the application

Requirements: Ruby 3.3+, Node 20+, and SQLite 3.8+.


```bash
bin/setup     # installs gems and npm packages, creates .env, prepares the database, and starts everything
```

After that, `bin/dev` alone is enough.

`bin/dev` uses [foreman](https://github.com/ddollar/foreman) to run the three
processes in `Procfile.dev`; if it is not installed, the script installs it on
the first run. Rails is pinned to port 3000 (foreman would use 5000 by default,
and the Redirect URI must match exactly).

Open <http://127.0.0.1:3000> and click **Connect Spotify** (or go directly to
`/spotify/connect`). Authorize once; the refresh token is stored encrypted, and
subsequent syncs happen automatically.

> Use `127.0.0.1:3000`, not `localhost:3000`—the address must match the
> registered Redirect URI.

## The site

The navigation has eight tabs, and the selected tab is reflected in the URL
(`?view=tracks`), so the browser's back button works:

- **Overview:** the recent feed, "SpotPlayer's Top Items" (Spotify's own
  algorithmic top artists and tracks, `user-top-read`—distinct from the
  locally-derived shelves below it), plus album and artist shelves.
- **Tracks:** the complete history, grouped by day.
- **Albums:** your recently played albums; opening one shows its full
  tracklist (`/albums/:id/tracks`) and, if a matching one exists, Discogs
  releases to buy it on.
- **Artists:** the artist grid; clicking one opens its page (`/artists/:id/tracks`),
  with highlights from your history and the top tracks returned by Spotify's API.
- **Listeners:** one card per person on the feed—what they just played, who they
  have on repeat, and their most played—with a name filter for when the roster
  grows. Names match without accents, so `joao` finds `João`. Note that this
  filter is the tab's own: the top bar's search looks inside tracks, and a card
  that disappeared because its owner played nothing matching would read as them
  having left.
- **Playlists:** your public playlists and each playlist's tracks, deep-linked
  at `/playlists/:id/tracks`.
- **Discogs:** the records you own, and which of their tracks Spotify can
  actually play. See below.

There is also a search (which filters only what is currently on screen) and a
time-period filter, which is the global lens—the artist page reads from the
already-filtered set, not from what is entered in the search.

The **autoplay** button in the footer, enabled by default, makes the player
advance to the next track automatically; the preference is stored in
`localStorage`. Next/previous navigates the list the track came from: if you
started playing on an artist page, the player stays there until you play
something else.

## Routes

Params and response shape for the `/api/*` endpoints are in [docs/API.md](docs/API.md);
`/api-docs` is the same reference as an interactive, owner-only Swagger UI (see below).

| Route | Access | Description |
| --- | --- | --- |
| `GET /` | public | React app |
| `GET /artists/:id/tracks` | public | Same React app, deep-linked to one artist's page |
| `GET /albums/:id/tracks` | public | Same React app, deep-linked to one album's tracks |
| `GET /playlists/:id/tracks` | public | Same React app, deep-linked to one playlist's tracks |
| `GET /api/plays?limit=&before=&listener=` | public | Cursor-paginated feed, optionally one listener |
| `GET /api/status` | public | Who is on the feed, and their play counts |
| `GET /api/artists/:id/tracks` | public | Artist top tracks (1-hour cache) |
| `GET /api/albums/:id/tracks` | public | Album tracks (1-hour cache) |
| `GET /api/albums/:id/discogs` | public | Already-resolved Discogs match for a Spotify album |
| `GET /api/albums/releases?title=&artist=` | public | Discogs releases matching a Spotify album (2-minute cache) |
| `GET /api/playlists` | public | Owner's public playlists (5-minute cache) |
| `GET /api/playlists/:id/tracks` | public | The playlist's own name/cover plus its tracks |
| `GET /api/top_items` | public | The owner's algorithmic top artists/tracks (6-hour cache) |
| `GET /api/tracks/youtube_matches?ids=` | public | Cached YouTube clip links for a batch of tracks (needs `YOUTUBE_API_KEY`) |
| `GET /api/tracks/:id/lyrics` | public | Cached lrclib.net lyrics (plain and, when available, synced) for one track |
| `GET /api/now_playing.svg` | public | Hotlinkable "now playing" badge (`?listener=` to scope to one person) — see below |
| `GET /api/discogs/status` | public | Whether the shelf is configured and answering |
| `GET /api/discogs/releases?list=&q=&genre=&sort=&page=` | public | The shelf's collection or wantlist (2-minute cache) |
| `GET /api/discogs/releases/:discogs_id` | public | One record, its tracklist, and its Spotify match |
| `GET /api-docs` | owner | Interactive Swagger UI over every `/api/*` endpoint above |
| `GET /metrics` | owner | Prometheus exposition format — point a Prometheus server's scrape config at it |
| `GET /spotify/owner?view=` | owner | Asks the browser for `ADMIN_PASSWORD`, then returns to the feed |
| `GET /spotify/connect` | owner | Starts OAuth for the owner |
| `GET /spotify/join/:token` | invite | Starts OAuth for a friend |
| `GET /spotify/callback` | state | Receives the code and saves tokens |
| `POST /spotify/sync` | public | Syncs every listener now, without waiting for the job (rate-limited to 5/min) |
| `GET/POST /spotify/invites` | owner | List and issue invite links |
| `DELETE /spotify/invites/:id` | owner | Revoke an unclaimed invite |
| `DELETE /spotify` | owner | Unlinks the owner |
| `DELETE /spotify/listeners/:id` | owner | Unlinks one listener |

Most public routes use the owner's Spotify quota, so they all pass through a
`rate_limit` of 60 requests per minute: a burst would cause a Spotify 429 for the
entire app, also blocking synchronization—and a blocked sync, with only 50 plays
stored on Spotify's side, means permanently lost history. Spotify responses are
cached to avoid repeating the call on every visit. `plays`, `status` and
`now_playing.svg` spend no Spotify quota at all—they read only the local
mirror—and `tracks/youtube_matches`/`tracks/:id/lyrics` spend YouTube's and
lrclib's own quotas instead, not Spotify's; the same rate limit still applies
to all of them to keep any one from being hammered.

`GET /api/now_playing.svg` is meant to be hotlinked from outside the app—a
GitHub profile README, a personal site:

```markdown
[![Now playing](https://your-domain/api/now_playing.svg)](https://your-domain/)
```

It renders whatever the local mirror last synced, not a live call to Spotify,
and guesses "still playing" from the track's own duration—so it can lag by up
to a sync cycle, but never spends anyone's Spotify quota no matter how often
it gets viewed.

`GET /metrics` is [Yabeda](https://github.com/yabeda-rb/yabeda) +
`yabeda-prometheus` + `yabeda-rails`—request counts, latency, view/DB time,
per controller action. It only shows up under an actual `rails server`/Puma
boot: `yabeda-rails` checks for `Rails::Server` before installing its
counters, so `bin/rails console`, `bin/rails test` and rake tasks correctly
see none of it—not a bug, just not a server.

`config/initializers/yabeda.rb` adds the two app-specific groups this app
actually needs given its rate-limited Spotify quota: `spotify_requests_total`
/ `spotify_request_duration_seconds` (recorded in `Spotify::Client#perform`,
labelled by endpoint with ids collapsed to `:id` so `fetch_each` doesn't mint
a series per track/artist) and `spotify_sync_runs_total` /
`spotify_sync_plays_imported_total` (recorded in
`Spotify::RecentlyPlayedSync#call`—the one place both the scheduled job and
the owner's "Sync now" button go through—labelled by listener and, for runs,
outcome). Add further app-specific metrics (Solid Queue backlog, YouTube/lrclib
lookup rates) the same way:

```ruby
Yabeda.configure do
  group :solid_queue
  gauge :backlog, comment: "Pending Solid Queue jobs", tags: %i[queue_name]
end
```

The `?view=metrics` tab (`Spotify::MetricsController`,
`app/frontend/components/MetricsView.jsx`) charts the same numbers without
leaving the app—no Prometheus required. Deliberately public, unlike the rest
of the owner-only surface: request counts, latency and sync outcomes are
operational detail, not anything private about a listener. `GET /metrics`
itself (the raw exposition format an actual Prometheus server scrapes) stays
behind `ADMIN_PASSWORD`, same as always. For history beyond "since this
process last booted", and for alerting, point an actual Prometheus + Grafana
at `/metrics`. Two ways to do that, depending on where this is deployed:

- **A host you control** (local, or a VPS via Kamal): `observability/docker-compose.yml`
  runs Prometheus + Grafana side by side, pre-wired with a datasource and a
  matching dashboard.
- **Railway** (or any PaaS with no SSH access to the box): `observability/railway/`
  runs a small Grafana Alloy service instead, which scrapes `/metrics` over
  Railway's private network and forwards it to a free Grafana Cloud stack—see
  `observability/railway/README.md`.

```bash
cp observability/prometheus.yml.example observability/prometheus.yml   # fill in ADMIN_PASSWORD
cd observability && docker compose up
```

Prometheus at `http://localhost:9090`, Grafana at `http://localhost:3300`
(`admin` / `admin` unless `GRAFANA_ADMIN_PASSWORD` is set). It scrapes the app
on the host via `host.docker.internal`, which is why `config/environments/development.rb`
adds that hostname to `config.hosts`—without it, Host Authorization answers
403 before `AdminBasicAuth` even runs. Against a deployed instance instead,
point `targets:` in `prometheus.yml` at the real host and add `scheme: https`.

Owner routes are protected by HTTP Basic with `ADMIN_PASSWORD` (the username can
be anything; only the password matters). In development, when the variable is
not set, protection is waived only for requests from the local machine—a server
bound to `0.0.0.0` or exposed through a tunnel still requires a password. In
production it is mandatory.

Manual sync:

```bash
bin/rails spotify:sync
# ou
curl -X POST http://127.0.0.1:3000/spotify/sync
```

The top-right **Sync** button does the same thing from the browser—no
`ADMIN_PASSWORD` needed, same as the rest of the public feed. It still spends
real Spotify quota, one request per connected account, so `Spotify::SyncsController`
rate-limits it to 5 requests/minute (a burst past that answers 429) and
`CrossSiteGuarded` still refuses a cross-site post, so another page a visitor
has open cannot trigger this on their behalf.

`/api-docs` is a Swagger UI you can fire real requests from, gated by the same
`ADMIN_PASSWORD` as the routes above. It reads `swagger/v1/swagger.yaml`, which
is hand-written rather than generated from specs—`rswag-specs` does that, but
requires RSpec, and this project tests with Minitest.

## Discogs

The Discogs tab shows the records you own and marks, track by track, what
Spotify will actually play.

The collection itself is **not** read from Discogs by this app. It comes from
[`discogs_shelf`](../discogs_shelf), the sibling app that already mirrors a
Discogs profile into its own database and serves it as JSON — sync, rate
limiting and the release cache are solved there, and a second copy here would
mean a second Discogs token and a second mirror of the same shelf. Point this
app at it:

```
DISCOGS_SHELF_URL=http://127.0.0.1:3001
```

Then run the shelf on that port (`bin/rails server -p 3001` in its repo; port
3000 is taken here) and sync it at least once. Without the variable the tab
explains what is missing instead of erroring.

```bash
bin/rails discogs:check   # is the shelf answering, and with what
bin/rails discogs:match   # match the whole collection up front
```

### How the matching works

Discogs and Spotify share no identifier, so the bridge is the text. For each
record: one album search, then one album fetch for its tracklist, then a capped
per-track search for whatever the album did not cover — which is what rescues a
record Spotify only carries as part of a compilation. Titles are compared by
word, ignoring bracketed asides, edition words ("Remastered", "- Live") and the
translation Discogs writes after a `=` on Brazilian pressings, so
`Exciter (Excitador)` meets `Exciter - Live`.

It is guesswork, and it is priced accordingly: the result is stored in
`discogs_matches` for 30 days and reused for every visitor. **Opening a record
is what spends the requests** — the grid only badges records that have already
been matched, and no badge means "not looked at yet", not "not on Spotify".
`bin/rails discogs:match` is the way to badge the whole grid in one go.

`SPOTIFY_MARKET` (an ISO country code) decides which catalogue is being judged.
Spotify only reports whether a track is playable when it is told a market, and
it only reveals the account's own country under `user-read-private`, which this
app deliberately does not ask listeners for. Without it, playability comes back
unknown and is taken at face value.

## The player

Each track opens in the fixed footer player, using the
[Spotify iframe embed](https://developer.spotify.com/documentation/embeds).
A single player remains on the page and changes tracks on each click.

What a person hears depends on who they are:

- **Not logged in to Spotify:** 30-second preview.
- **Logged in to Spotify:** the full track.

Premium and login to your site are not required. Spotify has deprecated the
API's `preview_url` field for new apps, so hosting the audio yourself is not a
viable alternative—the embed is the supported approach.

If Spotify's script does not load (because of an ad blocker, for example), the
app falls back to a simple `<iframe>` that still plays—it just requires one
extra click on the play button.

## Structure

```
app/
├── controllers/
│   ├── api/                  # base (rate limit), plays, status, artists,
│   │                         #   playlists, discogs (public JSON)
│   ├── concerns/
│   │   └── admin_authenticated.rb
│   └── spotify/              # sessions (OAuth), syncs
├── frontend/                 # React
│   ├── components/           # App, Sidebar, TopBar, Hero, Shelf, ArtistView,
│   │                         #   PlaylistView, DiscogsView, DiscogsRelease,
│   │                         #   PlayFeed, PlayRow, PlayerBar, SetupNotice, icons
│   ├── hooks/                # usePlays, useSpotifyEmbed
│   ├── images/               # logo and wordmark
│   ├── lib/                  # api.js, derive.js, format.js
│   └── styles/
├── jobs/
│   └── sync_recently_played_job.rb
├── models/                   # Track, Play, Artist, TrackArtist, SpotifyAccount,
│                             #   DiscogsMatch
└── services/
    ├── discogs_shelf/        # read-only client for the sibling shelf app
    └── spotify/              # client, authorization, recently_played_sync,
                              #   artist_backfill, release_matcher
```

`DiscogsMatch` is a cache, not a mirror: one row per Discogs release that
somebody has opened, holding which Spotify album it turned out to be and which
of its tracks are playable.

`Track` stores the song; `Play` stores each time it was played. The same track
played five times becomes one `Track` and five `Play` records. `Artist` exists
separately because the play payload does not include the artist's image—
`ArtistBackfill` fetches those images later when new artists appear.

## Quality

```bash
bin/rails test     # tests
bin/rubocop        # style
npm test           # frontend tests (Vitest)
```

The tests cover Spotify payload normalization, sync idempotency, token
encryption, cursor pagination, OAuth flow rejections, sync route protection,
artist and playlist endpoints, the Spotify HTTP client's own error mapping
(expired tokens, rate limits, incomplete responses), background job fan-out
and retry/discard behavior, and the race conditions around claiming an invite
or resolving the same Discogs match twice at once. The test environment uses
fixed encryption keys, so neither local tests nor CI need `master.key`. `npm test` covers
`app/frontend/lib/derive.js` and `lib/format.js`—the dependency-free logic the
feed, shelves and filters are derived from—via `*.test.js` files next to them.

The hook in `.githooks/pre-commit` runs RuboCop, a frontend build (`bin/vite
build`, so a broken JSX/JS file fails locally instead of only in CI), the
frontend tests, and the Rails tests before every commit. To enable it in a new
clone:

```bash
git config core.hooksPath .githooks
```

CI (`.github/workflows/ci.yml`) runs the same checks, plus the frontend build
and three vulnerability scans: Brakeman (Rails static analysis), bundler-audit
(known CVEs in gems) and `npm audit` (known CVEs in npm packages, dev
dependencies included — Vite builds the bundle this site ships).
`.github/workflows/codeql.yml` adds CodeQL over both Ruby and JavaScript, which
is what covers the browser-side OAuth and playback code that Brakeman does not
read; its findings land in the repository's Security tab.

Both workflows also run weekly on a schedule, because an advisory can be
published against a dependency nobody has touched. Dependabot watches the
bundler, npm and github-actions ecosystems.

`.github/workflows/dependency-review.yml` runs on every pull request and
blocks one that introduces a known-vulnerable or license-incompatible
dependency, summarized as a PR comment — this is a gate on what a PR is about
to add, distinct from bundler-audit/npm audit above, which only scan what is
already in the lockfile.

A CI failure on `main` (a push, or the weekly scheduled scan finding a new
advisory) opens a GitHub issue labeled `ci-failure` — or comments on the one
already open, rather than filing a new one every time. A PR failure does not,
since whoever opened it already sees it.

There is also a review skill in `.claude/skills/code-reviewer/`, used by Claude
Code.

## Deployment

`config/recurring.yml` already schedules synchronization in production, so you
only need to run Solid Queue (`bin/jobs`) alongside the web server.

Before exposing the site publicly:

- set `DATABASE_URL` to a PostgreSQL connection string (`config/database.yml`
  derives four logical databases from it—primary, cache, queue, cable—by
  suffixing the database name, mirroring the old per-purpose SQLite files);
- set `ADMIN_PASSWORD` (without it, owner routes refuse to work);
- generate `RAILS_MASTER_KEY` from `config/master.key`—it decrypts the Spotify
  tokens;
- register **both** production Redirect URIs (HTTPS) in the Spotify dashboard—
  `https://your-domain/spotify/callback` (set as `SPOTIFY_REDIRECT_URI`) and
  `https://your-domain/listen/callback` (computed automatically from
  `APP_HOST`, nothing to set)—the same "both, or one flow breaks" reasoning
  as local setup above;
- set `APP_HOST` to the canonical domain, which enables DNS rebinding
  protection (`/up` is excluded because the load balancer connects by IP).

The Content Security Policy is already enabled in
`config/initializers/content_security_policy.rb`: it allows `open.spotify.com`
in `script-src`/`frame-src`, images over HTTPS (covers come from CDNs that
Spotify may change without notice), and disallows `object-src` and embedding in
another page.

### Continuous deployment (Railway)

`.github/workflows/ci.yml`'s `deploy` job pushes to Railway automatically on
every push to `main`, but only after `scan_ruby`, `scan_js`, `lint` and `test`
have all passed—a red CI never reaches this job at all, so there is nothing
separate to gate on. It needs two things set on the repo (**Settings → Secrets
and variables → Actions**):

- `RAILWAY_TOKEN` (a **secret**)—a Railway **project token**, from the
  Railway dashboard: project → Settings → Tokens. A project token, not an
  account token, so a leaked CI secret can only touch this one project.
- `RAILWAY_SERVICE` (a **variable**, not a secret—it's just a name)—the
  Railway service this app is deployed as, so the deploy lands on the right
  one if the project also runs other services (`observability/railway/`'s
  Alloy service, say).

Railway itself builds the image from this repo's `Dockerfile` on every
deploy—the workflow only tells it to start one, via the
[Railway CLI](https://docs.railway.com/reference/cli-api)'s
`railway up --service "$RAILWAY_SERVICE" --detach`. Not tested against a real
Railway project as part of writing this—the CLI invocation follows Railway's
documented usage, but confirm the first deploy actually lands before relying
on it.

## Privacy

The site publishes what you listen to, and what anyone who accepts an invite
listens to. Only this is exposed: track name, artists, cover art, time, and the
listener's Spotify display name and avatar. Tokens are encrypted in the database
(Active Record Encryption) and never reach the frontend.

**Tell a friend this before you send them a link.** Spotify's consent screen says
the app will read their recently played tracks; it does not say the result goes
on a public web page. That part is on you.

Coming off the feed:

- `bin/rails "spotify:hide[id]"` takes a listener off the public feed while
  keeping their history and their sync.
- `bin/rails "spotify:unlink[id]"` unlinks them and **deletes their plays**.
- `DELETE /spotify` does the same for the owner.
