# Recently played

A site that shows the latest tracks played on your Spotify account—and on your
friends' accounts, once they've joined—and lets visitors listen to each track
without leaving the page.

- **Backend:** Ruby on Rails 8.1 (API + pages)
- **Frontend:** React 19 via Vite (`vite_rails`)
- **Database:** SQLite
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

Issue a single-use invite:

```bash
bin/rails "spotify:invite[Ana]"
# → http://your-site/spotify/join/<token>   (single use, expires in 7 days)
```

Send them the link. They authorize with Spotify and their plays start appearing
on the feed, tagged with their name. The link never exposes `ADMIN_PASSWORD`,
and only its digest is stored, so a database copy cannot be replayed into an
account link.

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
2. Under **Redirect URIs**, add exactly:
   `http://127.0.0.1:3000/spotify/callback`
   Spotify requires the loopback IP (`127.0.0.1`) and does not accept `localhost`.
3. Under **APIs used**, select **Web API**.
4. Copy the **Client ID** and **Client Secret**.

The app requests two scopes: `user-read-recently-played` (history) and
`playlist-read-private` (the playlists tab). If you connected the account before
the playlists tab existed, redo `/spotify/connect`—without the second scope, the
tab returns 403 and explains this on screen.

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

The navigation has five tabs, and the selected tab is reflected in the URL
(`?view=tracks`), so the browser's back button works:

- **Overview:** the recent feed, plus album and artist shelves.
- **Tracks:** the complete history, grouped by day.
- **Artists:** the artist grid; clicking one opens its page, with highlights from
  your history and the top tracks returned by Spotify's API.
- **Listeners:** one card per person on the feed—what they just played, who they
  have on repeat, and their most played—with a name filter for when the roster
  grows. Names match without accents, so `joao` finds `João`. Note that this
  filter is the tab's own: the top bar's search looks inside tracks, and a card
  that disappeared because its owner played nothing matching would read as them
  having left.
- **Playlists:** your public playlists and each playlist's tracks.

There is also a search (which filters only what is currently on screen) and a
time-period filter, which is the global lens—the artist page reads from the
already-filtered set, not from what is entered in the search.

The **autoplay** button in the footer, enabled by default, makes the player
advance to the next track automatically; the preference is stored in
`localStorage`. Next/previous navigates the list the track came from: if you
started playing on an artist page, the player stays there until you play
something else.

## Routes

| Route | Access | Description |
| --- | --- | --- |
| `GET /` | public | React app |
| `GET /api/plays?limit=&before=&listener=` | public | Cursor-paginated feed, optionally one listener |
| `GET /api/status` | public | Who is on the feed, and their play counts |
| `GET /api/artists/:id/tracks` | public | Artist top tracks (1-hour cache) |
| `GET /api/playlists` | public | Owner's public playlists (5-minute cache) |
| `GET /api/playlists/:id/tracks` | public | Tracks in a playlist |
| `GET /spotify/connect` | owner | Starts OAuth for the owner |
| `GET /spotify/join/:token` | invite | Starts OAuth for a friend |
| `GET /spotify/callback` | state | Receives the code and saves tokens |
| `POST /spotify/sync` | owner | Syncs every listener now, without waiting for the job |
| `GET/POST /spotify/invites` | owner | List and issue invite links |
| `DELETE /spotify/invites/:id` | owner | Revoke an unclaimed invite |
| `DELETE /spotify` | owner | Unlinks the owner |
| `DELETE /spotify/listeners/:id` | owner | Unlinks one listener |

Public routes use the owner's Spotify quota, so they all pass through a
`rate_limit` of 60 requests per minute: a burst would cause a Spotify 429 for the
entire app, also blocking synchronization—and a blocked sync, with only 50 plays
stored on Spotify's side, means permanently lost history. Spotify responses are
cached to avoid repeating the call on every visit.

Owner routes are protected by HTTP Basic with `ADMIN_PASSWORD` (the username can
be anything; only the password matters). In development, when the variable is
not set, protection is waived only for requests from the local machine—a server
bound to `0.0.0.0` or exposed through a tunnel still requires a password. In
production it is mandatory.

Manual sync:

```bash
bin/rails spotify:sync
# ou
curl -u owner:$ADMIN_PASSWORD -X POST http://127.0.0.1:3000/spotify/sync
```

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
│   │                         #   playlists (public JSON)
│   ├── concerns/
│   │   └── admin_authenticated.rb
│   └── spotify/              # sessions (OAuth), syncs
├── frontend/                 # React
│   ├── components/           # App, Sidebar, TopBar, Hero, Shelf, ArtistView,
│   │                         #   PlaylistView, PlayFeed, PlayRow, PlayerBar,
│   │                         #   SetupNotice, icons
│   ├── hooks/                # usePlays, useSpotifyEmbed
│   ├── images/               # logo and wordmark
│   ├── lib/                  # api.js, derive.js, format.js
│   └── styles/
├── jobs/
│   └── sync_recently_played_job.rb
├── models/                   # Track, Play, Artist, TrackArtist, SpotifyAccount
└── services/spotify/         # client, authorization, recently_played_sync,
                              #   artist_backfill
```

`Track` stores the song; `Play` stores each time it was played. The same track
played five times becomes one `Track` and five `Play` records. `Artist` exists
separately because the play payload does not include the artist's image—
`ArtistBackfill` fetches those images later when new artists appear.

## Quality

```bash
bin/rails test     # tests
bin/rubocop        # style
```

The tests cover Spotify payload normalization, sync idempotency, token
encryption, cursor pagination, OAuth flow rejections, sync route protection,
and artist and playlist endpoints. The test environment uses fixed encryption
keys, so neither local tests nor CI need `master.key`.

The hook in `.githooks/pre-commit` runs RuboCop and the tests before every
commit. To enable it in a new clone:

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

There is also a review skill in `.claude/skills/code-reviewer/`, used by Claude
Code.

## Deployment

`config/recurring.yml` already schedules synchronization in production, so you
only need to run Solid Queue (`bin/jobs`) alongside the web server. Since the
database is SQLite, the disk must be persistent.

Before exposing the site publicly:

- set `ADMIN_PASSWORD` (without it, owner routes refuse to work);
- generate `RAILS_MASTER_KEY` from `config/master.key`—it decrypts the Spotify
  tokens;
- register the production Redirect URI (HTTPS) in the Spotify dashboard and set
  `SPOTIFY_REDIRECT_URI`;
- set `APP_HOST` to the canonical domain, which enables DNS rebinding
  protection (`/up` is excluded because the load balancer connects by IP).

The Content Security Policy is already enabled in
`config/initializers/content_security_policy.rb`: it allows `open.spotify.com`
in `script-src`/`frame-src`, images over HTTPS (covers come from CDNs that
Spotify may change without notice), and disallows `object-src` and embedding in
another page.

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
