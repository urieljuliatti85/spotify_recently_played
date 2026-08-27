---
name: run-spotify-recently-played
description: Build, run, and drive the Recently Played app. Use when asked to start the app, launch the server, take a screenshot of the UI, check a view or tab renders, seed demo listeners, hit the JSON API, or run the test suite.
tags: ["run", "screenshot", "server", "rails", "vite"]
---

A Rails 8.1 + Vite + React app that mirrors Spotify listening history. Drive it
headlessly with **`.claude/skills/run-spotify-recently-played/driver.mjs`** — it
builds the bundle, starts Rails on its own port, seeds demo data, and
screenshots any tab. Paths below are relative to the repo root.

Do **not** reach for `bin/dev` + a browser to verify a UI change. It starts
`bin/jobs`, which syncs against the real Spotify API on the owner's token, and
headless Chrome will not render the app off the Vite dev server anyway (see
Gotchas).

## Prerequisites

macOS or Linux, plus Ruby (`.ruby-version` pins 3.3.11), Node, and a
Chrome/Chromium binary. This project has **no** `chromium-cli`, Playwright, or
Puppeteer — the driver shells out to a desktop Chrome and auto-detects it at
`/Applications/Google Chrome.app/…`, `/usr/bin/google-chrome`, `/usr/bin/chromium`.
Override with `CHROME=/path/to/binary`.

## Setup

```bash
bin/setup --skip-server     # bundle install, npm install, copies .env, db:prepare
```

`bin/setup` without the flag `exec`s straight into `bin/dev` and never returns —
always pass `--skip-server` from an agent.

No Spotify credentials are needed for anything below except the Playlists tab.
`.env` is created from `.env.example` with placeholder values and that is fine.

## Run (agent path)

```bash
node .claude/skills/run-spotify-recently-played/driver.mjs smoke
```

Builds assets, starts Rails on **3010**, seeds two demo listeners with ~33
plays, screenshots every offline tab into `tmp/driver/`, then unseeds and stops.
Takes about 20s. Exits non-zero on any failure.

Step by step, when you want to poke at something:

```bash
node .claude/skills/run-spotify-recently-played/driver.mjs up
node .claude/skills/run-spotify-recently-played/driver.mjs seed
node .claude/skills/run-spotify-recently-played/driver.mjs shot listeners
node .claude/skills/run-spotify-recently-played/driver.mjs api "/api/plays?limit=2"
node .claude/skills/run-spotify-recently-played/driver.mjs unseed
node .claude/skills/run-spotify-recently-played/driver.mjs down
```

| Command | What it does |
| --- | --- |
| `up` | `bin/vite build --mode development`, writes `public/preview.html`, starts Rails on 3010, polls `/up` and `/api/status` until both answer. Idempotent. |
| `down` | SIGTERMs **only** the pid it wrote; removes `public/preview.html`, `public/vite-dev` and `public/driver`. |
| `seed` | Two `DEMO-` listeners + 6 tracks + 33 plays, straight into SQLite. No network, no OAuth. |
| `unseed` | Deletes only rows whose `spotify_user_id` / `spotify_id` starts with `DEMO-`. |
| `shot <view> [out]` | Screenshots one tab to `tmp/driver/<view>.png`. Asserts the app mounted before trusting the pixels. |
| `api <path>` | GET a JSON endpoint off the running server, pretty-printed. |
| `smoke` | All of the above, in order. Teardown runs in a `finally`, so a failed screenshot still unseeds and stops the server. |

Views: `overview`, `tracks`, `artists`, `listeners`, `playlists`, `discogs`. They
map to the `?view=` query param the app already reads in `App.jsx#viewFromUrl`.
A view may carry extra query params after a `?` — `shot "discogs?release=1661091"`
screenshots one record instead of the grid (quote it, or zsh eats the `?`).

Env: `DRIVER_PORT` (default 3010), `DRIVER_OUT` (default `tmp/driver`), `CHROME`.

**Look at the screenshot.** `shot` fails loudly on a blank frame or an unmounted
app, but it cannot tell you the layout is wrong.

## Direct invocation

Most of the interesting frontend logic is dependency-free ESM and can be called
without a browser or a server — this is the fastest loop for changes to
`derive.js` / `format.js`:

```bash
node --input-type=module -e '
import { listenersFrom } from "./app/frontend/lib/derive.js"
const ana = { id: 1, name: "Ana", plays_count: 40 }
const plays = [{ id: 1, played_at: new Date().toISOString(), listener: ana,
                 track: { spotify_id: "x", name: "Duvet", artists: "Boa",
                          artist_list: [{ id: "boa", name: "Boa" }] } }]
console.log(JSON.stringify(listenersFrom(plays, [ana]), null, 2))
'
```

Ruby internals the same way, against the real dev database:

```bash
bin/rails runner 'p Play.on_the_feed.by_listener(1).count'
```

## Run (human path)

```bash
bin/dev        # rails :3000 + vite :3036 + solid_queue jobs
```

Port 3000 is pinned in `Procfile.dev` because Spotify's redirect URI has to
match exactly. Only useful with a real browser — and it will sync against
Spotify for real. Not the agent path.

## Test

```bash
bin/rails test      # 97 tests, runs in parallel across cores
bin/rubocop
bin/brakeman -q --no-pager
```

`bin/ci` runs setup, RuboCop, `bundler-audit` and Brakeman — read `config/ci.rb`
before assuming it covers you: **it does not run `bin/rails test`.**

The test database is separate from development, so the driver's `seed` cannot
affect it.

## Gotchas

- **Headless Chrome will not mount this app through the Vite dev server.** The
  page comes back blank — an empty `#app` and a ~10 KB PNG. It fails on the home
  page too, so it is not any one view's fault: the module graph is still
  resolving when the virtual clock runs out. This is the entire reason
  `driver.mjs` builds the bundle and serves it from a static `public/preview.html`
  instead. Don't "fix" the driver by pointing it at `/`.
- **Vite Ruby owns the `/vite-dev/` URL prefix, and it answers 404.** Whenever a
  dev server is reachable, its proxy middleware intercepts every
  `/vite-dev/*` request before Rails' static file server sees it — including the
  files `vite build` just wrote to `public/vite-dev/`. The symptom is brutal to
  read: the files are right there on disk and `curl` still gets a 404, so the
  preview page loads and `#app` stays empty. This is why `buildAssets()` copies
  everything to `public/driver/` and rewrites the absolute `/vite-dev/` URLs Vite
  baked into the bundle. **Testing the driver only with `bin/dev` stopped will not
  catch this** — that was a real bug in the first version of this skill.
- **`VITE_RUBY_SKIP_PROXY` and `VITE_RUBY_PORT` do not turn any of that off.**
  Rails also keeps emitting `/vite-dev/@vite/client` script tags on its own
  pages. The preview page sidesteps tag generation entirely by reading
  `public/vite-dev/.vite/manifest.json` itself.
- **Never `pkill -f "rails server"`.** It kills the developer's own `bin/dev`,
  and the stale `tmp/pids/server.pid` left behind then makes every later boot
  exit with `A server is already running`. The driver uses its own port and its
  own pidfile and only signals the pid it wrote. If you do hit that error:
  `rm -f tmp/pids/server.pid`.
- **`bin/jobs` spends real Spotify quota.** `SyncAllAccountsJob` runs every
  minute and syncs each linked account with its stored refresh token. The driver
  never starts it. Don't add it "for realism".
- **Screenshotting a half-booted Rails looks like a bug in the app.** You get
  "Couldn't load the tracks — /api/plays failed with 404", because the request
  landed before routes were ready. `up` polls `/api/status` for this reason;
  don't replace it with a `sleep`.
- **The Vite dev server binds IPv6-only.** `curl http://127.0.0.1:3036` gets
  connection refused while `curl http://[::1]:3036` answers. Don't conclude it's
  down.
- **CSP blocks the Vite HMR websocket** in dev: the client dials
  `ws://127.0.0.1:3036` while the policy allowlists `ws://localhost:3036`. It is
  noise in the console, not a failure — HMR just doesn't reconnect.
- **The Playlists tab needs live Spotify** (real credentials plus a linked
  account with `playlist-read-private`). It is excluded from `smoke`;
  `shot playlists` still works and will screenshot the error state, logging a
  note, rather than failing.
- **The Discogs tab needs the sibling `discogs_shelf` app running** at
  `DISCOGS_SHELF_URL` (`bin/rails server -p 3001` in `../discogs_shelf`), and
  opening a record spends real Spotify requests the first time. Like playlists,
  it is excluded from `smoke` and screenshots its own setup notice rather than
  failing. `bin/rails discogs:check` says whether the shelf is answering.
- **The demo owner never steals ownership.** `seed` only sets `owner: true` when
  no owner exists, so running it against a real database leaves the real owner
  alone.
- **`/favicon.ico` logs a RoutingError** on every page load. Harmless; there is
  no such route.
- **Quote paths containing `?`.** `driver.mjs api /api/plays?limit=2` dies with
  `zsh: no matches found` before Node ever sees it.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `FAIL: app did not mount at …` | The DOM is dumped to `tmp/driver/<view>.dom.html` — read it. If `#app` is empty and the bundle tag is present, `curl` the bundle URL: a 404 on a file that exists on disk means something is claiming the prefix (see the Vite Ruby proxy gotcha). |
| `FAIL: screenshot looks blank (N bytes)` | Same cause. Check `tmp/driver/rails.log`. |
| `A server is already running (pid …)` | Stale pidfile: `rm -f tmp/pids/server.pid`. The driver's own pidfile lives in `tmp/driver/`. |
| `Rails did not answer /up` | Read `tmp/driver/rails.log`; usually a migration is pending — `bin/rails db:prepare`. |
| `no Chrome/Chromium found` | `CHROME=/path/to/binary node …/driver.mjs shot listeners`. |
| `Cannot resolve entry module index.html` from Vite | You ran `vite build` from a subdirectory. `vite.config.ts` is at the repo root; run it from there. |
| Port 3010 already taken | `DRIVER_PORT=3011 node …/driver.mjs up`. |
